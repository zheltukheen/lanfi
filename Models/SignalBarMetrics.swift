import Foundation

/// Geometry for the signal/quality bar that shares a table cell with its number.
///
/// Kept free of AppKit so the arithmetic can be tested: the bar gets whatever
/// the number does not need, but never less than `minimumWidth` and never so
/// much that it crowds the figure in a narrow column.
enum SignalBarMetrics {
    /// Bar gutter, the gap after the bar and the cell's trailing inset.
    static let leadingGutter: Double = 5
    static let gap: Double = 6
    static let trailingInset: Double = 6

    static let minimumWidth: Double = 12
    /// The number keeps at least 40 % of the column reserved for itself, so a
    /// rounding error can never push the bar over the digits.
    static let maximumTextShare: Double = 0.6

    /// Clamps a measured text width to something usable. AppKit reports
    /// `NSView.noIntrinsicMetric` (-1) or the full, untruncated width for a
    /// label that is already squeezing its text, so both are bounded here.
    static func clampedTextWidth(_ width: Double, columnWidth: Double) -> Double {
        guard columnWidth > 0 else { return 0 }
        guard width.isFinite, width > 0 else { return 0 }
        return min(width.rounded(.up), columnWidth * maximumTextShare)
    }

    /// Width for the bar itself.
    static func barWidth(columnWidth: Double, textWidth: Double) -> Double {
        guard columnWidth > 0 else { return minimumWidth }
        let text = clampedTextWidth(textWidth, columnWidth: columnWidth)
        let available = columnWidth - text - leadingGutter - gap - trailingInset
        return max(minimumWidth, available)
    }
}
