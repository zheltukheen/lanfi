import SwiftUI

// MARK: - Buttons

enum AppButtonTone {
    case primary
    case secondary
    case quiet

    var foreground: Color {
        switch self {
        case .primary: return .white
        case .secondary: return .primary
        case .quiet: return .accentColor
        }
    }

    var background: Color {
        switch self {
        case .primary: return .accentColor
        case .secondary: return Color(nsColor: .controlBackgroundColor)
        case .quiet: return .clear
        }
    }

    var border: Color {
        switch self {
        case .primary: return .clear
        case .secondary: return Color.secondary.opacity(DesignToken.Toolbar.strokeOpacity)
        case .quiet: return .clear
        }
    }
}

/// The app's one button. Toolbars, cards and empty states use it instead of
/// mixing `.bordered`, `.borderedProminent`, `.link` and `.plain`, so a refresh
/// button looks the same in every tool.
struct AppButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var tone: AppButtonTone = .secondary
    var isBusy = false
    var help: LocalizedStringKey?
    var isEnabled = true

    let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        tone: AppButtonTone = .secondary,
        isBusy: Bool = false,
        help: LocalizedStringKey? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.isBusy = isBusy
        self.help = help
        self.isEnabled = isEnabled
        self.action = action
    }

    /// Variant for a title that is already localized at runtime (a computed
    /// `String`), so the call site does not have to build a `LocalizedStringKey`.
    init(
        localized title: String,
        systemImage: String? = nil,
        tone: AppButtonTone = .secondary,
        isBusy: Bool = false,
        help: LocalizedStringKey? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            LocalizedStringKey(title), systemImage: systemImage, tone: tone, isBusy: isBusy,
            help: help, isEnabled: isEnabled, action: action)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.tight) {
                if isBusy {
                    ProgressView().controlSize(.mini)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundColor(tone.foreground)
            .padding(.horizontal, DesignToken.Spacing.small)
            .frame(height: DesignToken.Toolbar.height)
            .background(
                tone.background, in: RoundedRectangle(cornerRadius: DesignToken.Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .strokeBorder(tone.border, lineWidth: DesignToken.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .help(help ?? title)
        .accessibilityLabel(Text(title))
    }
}

/// Icon-only variant of `AppButton` for a header strip.
struct AppIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var tone: AppButtonTone = .secondary
    var tint: Color?
    var isActive = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint ?? (isActive ? .accentColor : .primary))
                .frame(width: DesignToken.Toolbar.iconWidth)
                .frame(height: DesignToken.Toolbar.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appToolbarChrome(isActive: isActive)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityValue(isActive ? "On" : "")
    }
}

// MARK: - Lists

/// The app's one list row: optional glyph, title, optional subtitle, optional
/// trailing badge and a selection state. Sidebars, tool palettes and pickers
/// share it so the selection colour, padding and type scale never drift.
struct AppListRow: View {
    var icon: String?
    let title: String
    var subtitle: String?
    var trailingText: String?
    var isSelected = false
    var isEnabled = true
    var help: String?

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignToken.Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .frame(width: 17)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(
                                isSelected ? Color.white.opacity(0.75) : .secondary
                            )
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DesignToken.Spacing.tight)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, DesignToken.Spacing.tight)
                        .padding(.vertical, 1)
                        .background(
                            (isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12)),
                            in: Capsule())
                }
            }
            .padding(.horizontal, DesignToken.Spacing.small)
            .padding(.vertical, DesignToken.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary))
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help ?? title)
    }
}

// MARK: - Search

/// One search field for sidebars and tool headers.
struct AppSearchField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    var body: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .frame(height: DesignToken.Toolbar.height)
        .background(
            DesignToken.Surface.controlFill,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }
}

// MARK: - Header strip

/// One header strip for every toolkit screen: tabs or a title on the left,
/// actions on the right, the same padding and the divider underneath. Screens
/// no longer build their own `HStack` + `Divider`, which is why Connections and
/// Network Monitor used to read as two different apps.
struct ToolkitHeaderBar<Content: View, Trailing: View>: View {
    private let content: Content
    private let trailing: Trailing

    init(@ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignToken.Spacing.small) {
                content
                Spacer(minLength: 0)
                trailing
            }
            .padding(.horizontal, DesignToken.Layout.contentPadding)
            .padding(.vertical, DesignToken.Spacing.small)
            Divider()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension ToolkitHeaderBar where Trailing == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, trailing: { EmptyView() })
    }
}
