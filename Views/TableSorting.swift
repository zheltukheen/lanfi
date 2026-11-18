import Foundation

/// One comparable value extracted from a table row.
///
/// Every table sorts through `TableSorter`, so text, numbers and flags compare
/// the same way everywhere instead of each screen re-implementing a comparator.
enum SortValue: Comparable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case none

    static func text(_ value: String?) -> SortValue {
        guard let value, !value.isEmpty else { return .none }
        return .text(value)
    }

    static func number(_ value: Double?) -> SortValue {
        guard let value else { return .none }
        return .number(value)
    }

    static func number(_ value: Int?) -> SortValue {
        value.map { .number(Double($0)) } ?? .none
    }

    static func flag(_ value: Bool?) -> SortValue {
        value.map { .flag($0) } ?? .none
    }

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        switch (lhs, rhs) {
        case (.none, _): return false
        case (_, .none): return true
        case (.text(let left), .text(let right)):
            return left.localizedStandardCompare(right) == .orderedAscending
        case (.number(let left), .number(let right)):
            return left < right
        case (.flag(let left), .flag(let right)):
            return left == false && right == true
        default:
            return false
        }
    }
}

/// A sortable column: a stable id, its menu title and how to read the cell.
struct SortColumn<Row> {
    let id: String
    let title: String
    let value: (Row) -> SortValue
}

/// Shared table sorter. Owns the selected column and direction, and keeps the
/// original order for equal values so sorting never shuffles rows around.
final class TableSorter<Row>: ObservableObject {
    let columns: [SortColumn<Row>]

    @Published var key: String
    @Published var ascending: Bool

    init(columns: [SortColumn<Row>], initialKey: String, ascending: Bool = true) {
        self.columns = columns
        self.key = initialKey
        self.ascending = ascending
    }

    var options: [(key: String, title: String)] {
        columns.map { ($0.id, $0.title) }
    }

    func sorted(_ rows: [Row]) -> [Row] {
        guard let column = columns.first(where: { $0.id == key }) else { return rows }
        let ordered = rows.enumerated().sorted { lhs, rhs in
            let left = column.value(lhs.element)
            let right = column.value(rhs.element)
            if left == right { return lhs.offset < rhs.offset }
            return ascending ? left < right : right < left
        }
        return ordered.map(\.element)
    }
}
