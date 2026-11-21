import CoreGraphics

/// Column geometry for `AppTable`.
///
/// The table used to give every column its minimum width and let a trailing
/// `Spacer` swallow the rest, so columns huddled at the left edge of a half
/// empty card. This type decides the widths instead: the leftover space is
/// shared out, a hand-dragged width is honoured, and a widened column borrows
/// its space from the flexible ones down to their minimums.
enum TableColumnLayout {
    /// A column never goes below this, however narrow the card is: the sort
    /// chevron and two characters no longer fit after that.
    static let minColumnWidth: CGFloat = 56

    static func widths(
        minimums: [CGFloat],
        overrides: [Int: CGFloat],
        available: CGFloat
    ) -> [CGFloat] {
        guard !minimums.isEmpty else { return [] }
        let floors = minimums.map { max(minColumnWidth, $0) }
        var widths = floors
        for (index, override) in overrides where widths.indices.contains(index) {
            widths[index] = max(floors[index], override)
        }

        let total = widths.reduce(0, +)
        if total > available {
            let flexible = widths.indices.filter { overrides[$0] == nil && widths[$0] > floors[$0] }
            let capacity = flexible.reduce(0) { $0 + (widths[$1] - floors[$1]) }
            guard capacity > 0 else { return widths }
            let take = min(total - available, capacity)
            for index in flexible {
                widths[index] -= take * (widths[index] - floors[index]) / capacity
            }
            return widths
        }
        guard available > total else { return widths }

        let flexible = widths.indices.filter { overrides[$0] == nil }
        let extra = available - total
        if flexible.isEmpty {
            // Every column was sized by hand: share the leftover equally rather
            // than leave a gap at the right edge.
            let share = extra / CGFloat(widths.count)
            for index in widths.indices { widths[index] += share }
        } else {
            let base = flexible.reduce(0) { $0 + widths[$1] }
            for index in flexible {
                widths[index] += extra * widths[index] / max(1, base)
            }
        }
        return widths
    }
}
