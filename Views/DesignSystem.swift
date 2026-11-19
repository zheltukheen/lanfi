import SwiftUI

/// Shared visual contract for the app: spacing, radii, strokes and semantic
/// colours live here so screens stop inventing their own numbers.
enum DesignToken {
    enum Spacing {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let compact: CGFloat = 10
        static let card: CGFloat = 14
        static let sheet: CGFloat = 20
        static let section: CGFloat = 24
        static let emptyState: CGFloat = 30
        static let emptyStateWide: CGFloat = 36
    }

    enum Radius {
        static let tiny: CGFloat = 2
        static let badge: CGFloat = 4
        static let control: CGFloat = 7
        static let card: CGFloat = 10
        static let sheet: CGFloat = 14
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 1.5
    }

    /// Shared geometry. Screens used to hard-code `.padding(20)` and
    /// `.frame(minWidth: 600, minHeight: 420)` independently; these values keep
    /// sheets, panels and windows on one rhythm.
    enum Layout {
        static let contentPadding: CGFloat = 18
        static let sheetPadding: CGFloat = 20
        static let windowMinWidth: CGFloat = 980
        static let windowMinHeight: CGFloat = 640
        static let sheetWidth: CGFloat = 620
        static let sheetWidthCompact: CGFloat = 470
        static let sheetWidthWide: CGFloat = 900
        static let emptyStatePadding: CGFloat = 36
        static let sheetMinHeight: CGFloat = 430
        static let settingsWidth: CGFloat = 880
        static let settingsHeight: CGFloat = 660
        static let settingsSidebarMin: CGFloat = 180
        static let settingsSidebarIdeal: CGFloat = 200
        static let settingsSidebarMax: CGFloat = 240
        static let inspectorWidth: CGFloat = 268
        static let controlWidthSmall: CGFloat = 100
        static let controlWidth: CGFloat = 240
        static let controlWidthLarge: CGFloat = 320
        static let formLabelColumn: CGFloat = 120
    }

    /// One toolbar rhythm for the Wi-Fi workspace and the toolkit header.
    enum Toolbar {
        static let height: CGFloat = 28
        static let iconWidth: CGFloat = 32
        static let spacing: CGFloat = 8
        static let strokeOpacity: Double = 0.2
        static let activeStrokeOpacity: Double = 0.55
    }
}

/// Semantic colour roles. System colours adapt to light/dark and to the
/// increased-contrast setting on their own, so no per-appearance branches.
enum AppPalette {
    static var ok: Color { color(.success) ?? .green }
    static var warning: Color { color(.warning) ?? .orange }
    static var danger: Color { color(.danger) ?? .red }
    static let info: Color = .blue
    static let muted: Color = .secondary

    static func band(_ band: WiFiBand) -> Color {
        switch band {
        case .band24: return color(.band24) ?? .blue
        case .band5: return color(.band5) ?? .purple
        case .band6: return color(.band6) ?? .teal
        case .unknown: return .gray
        }
    }

    static func quality(_ score: Int) -> Color {
        switch QualityGrade(score: score) {
        case .excellent: return color(.excellent) ?? .green
        case .good: return color(.good) ?? .mint
        case .fair: return color(.fair) ?? .orange
        case .poor: return color(.poor) ?? .red
        }
    }

    /// `nil` unless the user opted into the colour-blind-safe palette.
    private static func color(_ role: AccessibilityPalette.Role) -> Color? {
        guard AccessibilityPalette.isEnabled else { return nil }
        let rgb = AccessibilityPalette.safeColor(for: role)
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

// MARK: - Surfaces

struct AppCard<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    init(padding: CGFloat = DesignToken.Spacing.medium, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.card)
                    .strokeBorder(
                        Color.primary.opacity(0.08), lineWidth: DesignToken.Stroke.hairline)
            )
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
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
                    .font(.system(size: 9, weight: .semibold))
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
                .font(.system(size: 17, weight: .semibold, design: .rounded))
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
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(tint ?? (isActive ? .accentColor : .primary))
                .frame(width: DesignToken.Toolbar.iconWidth)
        }
        .buttonStyle(.borderless)
        .appToolbarChrome(isActive: isActive)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityValue(isActive ? "On" : "")
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
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(LocalizedStringKey(title))
                .font(.caption)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .foregroundColor(isActive ? .accentColor : .primary)
        .padding(.horizontal, DesignToken.Spacing.small)
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
