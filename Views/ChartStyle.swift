import SwiftUI

/// One visual contract for every Swift Charts surface: axes, grid, cursor and
/// tooltip. Charts that hand-roll their own colours drift apart quickly, so new
/// marks should use these values instead of literals.
enum ChartStyle {
    static let axisLabelFont = Font.caption2
    static let axisLabelColor = Color.secondary

    static let gridStroke = StrokeStyle(lineWidth: 0.5, dash: [4, 4])
    static let gridColor = Color.secondary.opacity(0.18)

    static let cursorStroke = StrokeStyle(lineWidth: 1, dash: [5, 5])
    static let cursorColor = Color.primary.opacity(0.35)

    static let noiseColor = Color.secondary
    static let noiseStroke = StrokeStyle(lineWidth: 1.2, dash: [3, 3])
    static let noiseOpacity: Double = 0.55

    static let tooltipPadding = DesignToken.Spacing.tight
    static let tooltipRadius = DesignToken.Radius.control

    /// Compact, axis-free sparkline used by the menu bar and throughput card.
    /// The stroke is one step heavier than the grid so it survives template
    /// rendering in a light or dark menu bar.
    static let sparklineStroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
    static let sparklineFillOpacity: Double = 0.22
    static let sparklineBaselineOpacity: Double = 0.45
}

extension View {
    /// Tooltip/chip background shared by every chart annotation.
    func chartTooltipSurface(tint: Color = .primary) -> some View {
        padding(ChartStyle.tooltipPadding)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: ChartStyle.tooltipRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ChartStyle.tooltipRadius)
                    .strokeBorder(tint.opacity(0.12), lineWidth: DesignToken.Stroke.hairline)
            )
    }
}
