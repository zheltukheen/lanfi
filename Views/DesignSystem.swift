import SwiftUI

// MARK: - Surfaces

/// Horizontal inset a card applies to its content. `AppTable` reads it so a
/// table can bleed to the card's edges while ordinary text keeps the inset.
private struct CardContentPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var cardContentPadding: CGFloat {
        get { self[CardContentPaddingKey.self] }
        set { self[CardContentPaddingKey.self] = newValue }
    }
}

struct AppCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = DesignToken.Spacing.medium, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.cardContentPadding, padding)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardSurface()
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .appSectionLabel()
    }
}

// MARK: - Status

enum StatusTone {
    case neutral
    case good
    case warning
    case bad
    case info

    var color: Color {
        switch self {
        case .neutral: return AppPalette.muted
        case .good: return AppPalette.ok
        case .warning: return AppPalette.warning
        case .bad: return AppPalette.danger
        case .info: return AppPalette.info
        }
    }
}

struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral
    var icon: String?

    var body: some View {
        HStack(spacing: DesignToken.Spacing.hairline + 2) {
            if let icon {
                Image(systemName: icon)
                    .font(Theme.Typography.badge)
                    .foregroundColor(tone.color)
            } else {
                Circle()
                    .fill(tone.color)
                    .frame(width: 6, height: 6)
            }
            Text(verbatim: text)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .padding(.vertical, DesignToken.Spacing.hairline + 1)
        .background(tone.color.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
            Text(verbatim: value)
                .font(Theme.Typography.metric)
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct BandChip: View {
    let band: WiFiBand

    private var name: String {
        switch band {
        case .band24: return "2.4 GHz"
        case .band5: return "5 GHz"
        case .band6: return "6 GHz"
        case .unknown: return "Other"
        }
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Circle()
                .fill(AppPalette.band(band))
                .frame(width: 6, height: 6)
            Text(verbatim: name)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .padding(.vertical, DesignToken.Spacing.hairline + 1)
        .background(AppPalette.band(band).opacity(0.12), in: Capsule())
        .accessibilityLabel("Band \(name)")
    }
}

/// One toggle chip for filters, bands and scan modes. The selected state uses
/// the tinted surface pair, so a chip in the analyzer bar and one in the filter
/// popover read as the same control.
struct AppChip: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .accentColor
    var isOn: Bool
    var badge: String? = nil

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.tight) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(verbatim: title)
                    .lineLimit(1)
                if let badge {
                    Text(verbatim: badge)
                        .font(Theme.Typography.badge)
                        .padding(.horizontal, DesignToken.Spacing.tight)
                        .padding(.vertical, 1)
                        .background(DesignToken.Surface.tintFill(tint), in: Capsule())
                }
            }
            .font(Theme.Typography.chip)
            .foregroundColor(isOn ? tint : .secondary)
            .padding(.horizontal, DesignToken.Spacing.tight)
            .frame(minWidth: DesignToken.Control.chipMinWidth, minHeight: DesignToken.Toolbar.height)
            .background(
                isOn ? DesignToken.Surface.tintFill(tint) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .stroke(
                        isOn ? DesignToken.Surface.tintStroke(tint) : DesignToken.Surface.border,
                        lineWidth: DesignToken.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Toolbar

extension View {
    /// The shared toolbar chrome: one height, one radius, one stroke. Apply it
    /// to the label of a toolbar button or menu so every control on the bar
    /// reads as the same family.
    func appToolbarChrome(isActive: Bool = false) -> some View {
        frame(height: DesignToken.Toolbar.height)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .strokeBorder(
                        isActive
                            ? Color.accentColor.opacity(DesignToken.Toolbar.activeStrokeOpacity)
                            : Color.secondary.opacity(DesignToken.Toolbar.strokeOpacity),
                        lineWidth: DesignToken.Stroke.hairline)
            )
    }
}

/// Icon-only toolbar control with the shared chrome and a mandatory tooltip and
/// accessibility label, so no new unlabelled glyph reaches a toolbar.
struct ToolbarIconButton: View {
    let systemImage: String
    let label: String
    let help: String
    var isActive = false
    var tint: Color?

    let action: () -> Void

    var body: some View {
        AppIconButton(
            systemImage: systemImage,
            label: LocalizedStringKey(label),
            tint: tint,
            isActive: isActive,
            action: action
        )
        .help(help)
    }
}

/// One label + chrome for every dropdown in the app.
///
/// Menus used to be a mix of bare `Picker`s, icon-only menus and full-width
/// labels. A `Menu` with this label reads as the same control on the analyzer
/// toolbar, the filter bar and the toolkit headers, and it always shows the
/// current value plus the chevron that says "this opens a list".
struct AppMenuLabel: View {
    let title: String
    var systemImage: String?
    var isActive = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.menuIcon)
            }
            Text(LocalizedStringKey(title))
                .font(.caption)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.chevron)
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(isActive ? .accentColor : .primary)
        .padding(.horizontal, Theme.Control.horizontalPadding)
        .appToolbarChrome(isActive: isActive)
        .accessibilityHidden(true)
    }
}

/// Icon-only dropdown label: same chrome and side padding as `AppMenuLabel`,
/// so a gear or a share glyph is not a tighter button than the text menus next
/// to it. Menus without a title used to frame the glyph directly, which left
/// the icon touching the edge of its control.
struct AppIconMenuLabel: View {
    let systemImage: String
    var isActive = false

    var body: some View {
        Image(systemName: systemImage)
            .font(Theme.Typography.menuIcon)
            .foregroundColor(isActive ? .accentColor : .primary)
            .frame(width: Theme.Control.iconWidth - Theme.Control.horizontalPadding * 2)
            .padding(.horizontal, Theme.Control.horizontalPadding)
            .appToolbarChrome(isActive: isActive)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The shared dropdown chrome: borderless, intrinsic width, no bezel — the
    /// label carries the chrome via `appToolbarChrome`/`AppMenuLabel`.
    func appMenuStyle() -> some View {
        menuStyle(.borderlessButton)
            .fixedSize()
    }
}
