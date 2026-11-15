import Foundation

/// Summary statistics for one rolling signal series.
///
/// Values are kept in dBm or percent depending on the caller; the type only
/// describes the distribution, not the unit.
struct HistoryStatistics: Equatable {
    let count: Int
    let minimum: Int
    let maximum: Int
    let average: Double
    let p95: Int

    init?(values: [Int]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        count = sorted.count
        minimum = sorted[0]
        maximum = sorted[sorted.count - 1]
        average = Double(values.reduce(0, +)) / Double(values.count)
        let rank = Int(ceil(Double(values.count) * 0.95)) - 1
        p95 = sorted[max(0, min(sorted.count - 1, rank))]
    }

    var averageRounded: Int { Int(average.rounded()) }
}
