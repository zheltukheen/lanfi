import SwiftUI

/// The app's single design contract.
///
/// Every screen, panel and sheet reads its spacing, radii, strokes, layout
/// sizes, typography, surfaces and control metrics from here. A number that
/// describes how the app looks belongs in this file; a screen that invents its
/// own is a bug, not a style. `DesignToken` and `AppPalette` remain as aliases
/// of `Theme` and `Theme.Palette` so the rest of the codebase keeps its
/// call sites while the values themselves live in exactly one place.
enum Theme {
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
        /// Wide enough for the sidebar, the table with its default columns and
        /// the 300 pt inspector at once; below this the toolbar wraps and
        /// controls start overlapping.
        static let windowMinWidth: CGFloat = 1160
        static let windowMinHeight: CGFloat = 700
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

    /// Semantic type. Fonts are declared by role, not by point size at the call
    /// site, so a label, a badge and a chevron cannot drift apart between
    /// screens that should look the same.
    enum Typography {
        /// Section headers inside cards and panels.
        static let sectionLabel = Font.system(size: 10, weight: .semibold)
        /// Inline “key” text beside a value.
        static let caption = Font.caption
        /// Table column headers. Larger than a section label because a header
        /// sits next to the data it names, not above a card.
        static let tableHeader = Font.system(size: 12, weight: .semibold)
        /// Smallest legible label: chart annotations, pills, chips.
        static let micro = Font.system(size: 8, weight: .semibold)
        /// One-letter or one-digit glyphs in status pills and badges.
        static let badge = Font.system(size: 9, weight: .semibold)
        /// Chevrons and other disclosure glyphs.
        static let chevron = Font.system(size: 8, weight: .semibold)
        /// Icons inside menus and filters.
        static let menuIcon = Font.system(size: 10, weight: .semibold)
        /// Icons inside text buttons.
        static let controlIcon = Font.system(size: 11, weight: .semibold)
        /// Icons inside icon-only toolbar buttons.
        static let toolbarIcon = Font.system(size: 12, weight: .medium)
        /// Large numbers: stat tiles and summary blocks.
        static let metric = Font.system(size: 17, weight: .semibold, design: .rounded)
        /// Addresses, MACs, ports and other machine text.
        static let code = Font.system(size: 11, design: .monospaced)
    }

    /// Role-based colours for surfaces, borders and fills. System colours adapt
    /// to light/dark and increased contrast on their own.
    enum Surface {
        /// Content card background.
        static let card = Color(nsColor: .textBackgroundColor)
        /// A panel that sits directly on the window background (toolbars,
        /// sidebars, secondary strips).
        static let panel = Color(nsColor: .controlBackgroundColor)
        /// Hairline around a card.
        static let cardStroke = Color.primary.opacity(0.08)
        /// Hairline around a control or a nested panel.
        static let border = Color.secondary.opacity(0.12)
        /// Column and section rule inside a table or list. Stronger than a
        /// card border: it has to separate data, not just an edge.
        static let divider = Color.secondary.opacity(0.22)
        /// Very light fill behind an alternating row or an inset block.
        static let subtleFill = Color.secondary.opacity(0.06)
        /// Fill behind a warning banner or block.
        static let warningFill = Color.orange.opacity(0.10)
        /// Fill behind a failure banner or block.
        static let dangerFill = Color.red.opacity(0.10)
        /// Fill of a control that needs to stand off its bar (search fields,
        /// inline chips in a toolbar).
        static let controlFill = Color.secondary.opacity(0.09)
        /// Fill behind an informational banner.
        static let accentFill = Color.accentColor.opacity(0.08)
        /// Fill behind a selected row.
        static let selectionFill = Color.accentColor.opacity(0.16)
        /// Fill of a card tinted with a band, status or category colour.
        static func tintFill(_ color: Color) -> Color { color.opacity(0.12) }
        /// Hairline of a tinted card.
        static func tintStroke(_ color: Color) -> Color { color.opacity(0.30) }
    }

    /// Control metrics. A button, an icon button and a menu label share these
    /// so every control on a bar is the same height.
    enum Control {
        static let height = Toolbar.height
        static let iconWidth = Toolbar.iconWidth
        static let horizontalPadding = Spacing.small
        static let iconSpacing = Spacing.tight
        static let borderWidth = Stroke.hairline
    }

    /// Semantic colour roles. System colours adapt to light/dark and to the
    /// increased-contrast setting on their own, so no per-appearance branches.
    enum Palette {
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
}

/// Backwards-compatible names. The values live in `Theme`.
typealias DesignToken = Theme
typealias AppPalette = Theme.Palette

// MARK: - Shared surfaces

extension View {
    /// The one card surface: fill, rounded corners and a hairline border.
    /// The one card surface. `tint` replaces the neutral fill and hairline with
    /// the tint at panel strength, so a band- or status-coloured card is still
    /// the same object with the same radius and stroke width.
    func appCardSurface(
        radius: CGFloat = Theme.Radius.card,
        fill: Color = Theme.Surface.card,
        tint: Color? = nil,
        strokeWidth: CGFloat = Theme.Stroke.hairline
    ) -> some View {
        let surface = tint.map(Theme.Surface.tintFill) ?? fill
        let stroke = tint.map(Theme.Surface.tintStroke) ?? Theme.Surface.cardStroke
        return background(surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            )
    }

    /// Nested panel inside a card: border only, no second fill.
    func appPanelBorder(
        radius: CGFloat = Theme.Radius.control
    ) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Theme.Surface.border, lineWidth: Theme.Stroke.hairline)
        )
    }

    /// The section-header type used above tables, in cards and in inspectors:
    /// uppercased, tracked, semibold and secondary. Screens apply this instead
    /// of rebuilding the same four modifiers.
    func appSectionLabel() -> some View {
        font(Theme.Typography.sectionLabel)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}
