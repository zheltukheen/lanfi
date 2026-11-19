import SwiftUI

/// One description of a column in `AppTable`: a stable id, its title, how to
/// sort it and how to draw a cell.
struct AppTableColumn<Row> {
    let id: String
    let title: String
    var minWidth: CGFloat = 70
    var alignment: HorizontalAlignment = .leading
    let value: (Row) -> SortValue
    let cell: (Row) -> AnyView

    /// Builds a column from a plain view builder, so call sites do not wrap
    /// every cell in `AnyView` by hand.
    init<Cell: View>(
        id: String,
        title: String,
        minWidth: CGFloat = 70,
        alignment: HorizontalAlignment = .leading,
        value: @escaping (Row) -> SortValue,
        @ViewBuilder cell: @escaping (Row) -> Cell
    ) {
        self.id = id
        self.title = title
        self.minWidth = minWidth
        self.alignment = alignment
        self.value = value
        self.cell = { AnyView(cell($0)) }
    }
}

/// The app's single SwiftUI table builder.
///
/// Every SwiftUI table (comparison panels, toolkit lists) is built here so the
/// header, sort affordance, striping, row density and alignment are the same
/// everywhere, and sorting works by default through the shared `TableSorter`.
struct AppTable<Row: Identifiable>: View {
    let columns: [AppTableColumn<Row>]
    let rows: [Row]
    private let selection: Binding<Row.ID?>?
    private let rowMenu: ((Row) -> AnyView)?
    @StateObject private var sorter: TableSorter<Row>
    @Environment(\.appTableDensity) private var density

    init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            selection: nil, rowMenu: nil)
    }

    /// A table whose rows can be selected and opened with a context menu.
    init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true,
        selection: Binding<Row.ID?>?
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            selection: selection, rowMenu: nil)
    }

    init<Menu: View>(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true,
        selection: Binding<Row.ID?>? = nil,
        @ViewBuilder rowMenu: @escaping (Row) -> Menu
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            selection: selection, rowMenu: { AnyView(rowMenu($0)) })
    }

    private init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool,
        selection: Binding<Row.ID?>?, rowMenu: ((Row) -> AnyView)?
    ) {
        self.columns = columns
        self.rows = rows
        self.selection = selection
        self.rowMenu = rowMenu
        _sorter = StateObject(
            wrappedValue: TableSorter(
                columns: columns.map {
                    SortColumn(id: $0.id, title: $0.title, value: $0.value)
                },
                initialKey: initialKey,
                ascending: ascending))
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, striped: index.isMultiple(of: 2))
                        Divider().opacity(0.35)
                    }
                }
            }
            .padding(.horizontal, DesignToken.Spacing.tight)
            .padding(.bottom, DesignToken.Spacing.tight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sortable table")
    }

    private var sortedRows: [Row] {
        sorter.sorted(rows)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.medium) {
            ForEach(columns, id: \.id) { column in
                Button {
                    if sorter.key == column.id {
                        sorter.ascending.toggle()
                    } else {
                        sorter.key = column.id
                        sorter.ascending = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(column.title)
                        if sorter.key == column.id {
                            Image(systemName: sorter.ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                    }
                    .font(.caption2.bold())
                    .foregroundColor(sorter.key == column.id ? .primary : .secondary)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .frame(minWidth: column.minWidth, alignment: alignment(for: column))
                .contentShape(Rectangle())
                .help("Sort by \(column.title)")
                .accessibilityLabel("Sort by \(column.title)")
                .accessibilityValue(
                    sorter.key == column.id ? (sorter.ascending ? "Ascending" : "Descending") : "")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignToken.Spacing.tight)
    }

    private func rowView(_ row: Row, striped: Bool) -> some View {
        let isSelected = selection?.wrappedValue == row.id
        return HStack(alignment: .center, spacing: DesignToken.Spacing.medium) {
            ForEach(columns, id: \.id) { column in
                column.cell(row)
                    .frame(minWidth: column.minWidth, alignment: alignment(for: column))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, max(1, (density.rowHeight - 16) / 2))
        .contentShape(Rectangle())
        .onTapGesture {
            guard let selection else { return }
            selection.wrappedValue = row.id
        }
        .contextMenu {
            if let rowMenu { rowMenu(row) }
        }
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : (striped ? Color.secondary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.tiny)
        )
    }

    private func alignment(for column: AppTableColumn<Row>) -> Alignment {
        switch column.alignment {
        case .trailing: return .trailing
        case .center: return .center
        default: return .leading
        }
    }
}
