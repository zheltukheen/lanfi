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

    func sorted(_ rows: [Row], grouping: AppTableGrouping<Row>? = nil) -> [Row] {
        guard let column = columns.first(where: { $0.id == key }) else { return rows }
        guard let grouping else {
            return sortedRows(rows, by: column)
        }

        // A hierarchical list cannot be sorted as one array: that would put a
        // group's children next to unrelated rows. Split it into sections, sort
        // the sections by their header row and sort each section's children
        // among themselves, so a group always stays above its own rows. A row
        // above the first header (if any) becomes a headerless section and
        // sorts after the groups.
        var sections: [(header: Row?, body: [Row])] = []
        for row in rows {
            if grouping.isSectionStart(row) {
                sections.append((row, []))
            } else if sections.isEmpty {
                sections.append((nil, [row]))
            } else {
                sections[sections.count - 1].body.append(row)
            }
        }

        let orderedSections = sections.enumerated().sorted { lhs, rhs in
            switch (lhs.element.header, rhs.element.header) {
            case let (left?, right?):
                let leftValue = column.value(left)
                let rightValue = column.value(right)
                if leftValue == rightValue { return lhs.offset < rhs.offset }
                return ascending ? leftValue < rightValue : rightValue < leftValue
            case (nil, nil):
                return lhs.offset < rhs.offset
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }

        return orderedSections.flatMap { section -> [Row] in
            let body = sortedRows(section.element.body, by: column)
            return section.element.header.map { [$0] + body } ?? body
        }
    }

    private func sortedRows(_ rows: [Row], by column: SortColumn<Row>) -> [Row] {
        rows.enumerated().sorted { lhs, rhs in
            let left = column.value(lhs.element)
            let right = column.value(rhs.element)
            if left == right { return lhs.offset < rhs.offset }
            return ascending ? left < right : right < left
        }.map(\.element)
    }
}
