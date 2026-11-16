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
        static let section: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 10
        static let sheet: CGFloat = 14
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let emphasis: CGFloat = 1.5
    }
}

/// Semantic colour roles. System colours adapt to light/dark and to the
/// increased-contrast setting on their own, so no per-appearance branches.
enum AppPalette {
    static let ok: Color = .green
    static let warning: Color = .orange
    static let danger: Color = .red
    static let info: Color = .blue
    static let muted: Color = .secondary

    static func band(_ band: WiFiBand) -> Color {
        switch band {
        case .band24: return .blue
        case .band5: return .purple
        case .band6: return .teal
        case .unknown: return .gray
        }
    }

    static func quality(_ score: Int) -> Color {
        switch QualityGrade(score: score) {
        case .excellent: return .green
        case .good: return .mint
        case .fair: return .orange
        case .poor: return .red
        }
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
