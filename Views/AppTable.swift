import SwiftUI

/// One description of a column in `AppTable`: a stable id, its title, how to
/// sort it and how to draw a cell.
struct AppTableColumn<Row> {
    let id: String
    let title: String
    var minWidth: CGFloat = 70
    var alignment: HorizontalAlignment = .leading
    /// False for action or decoration columns, whose header must not offer a
    /// sort the table cannot perform.
    var isSortable: Bool = true
    let value: (Row) -> SortValue
    let cell: (Row) -> AnyView

    /// Builds a column from a plain view builder, so call sites do not wrap
    /// every cell in `AnyView` by hand.
    init<Cell: View>(
        id: String,
        title: String,
        minWidth: CGFloat = 70,
        alignment: HorizontalAlignment = .leading,
        isSortable: Bool = true,
        value: @escaping (Row) -> SortValue,
        @ViewBuilder cell: @escaping (Row) -> Cell
    ) {
        self.id = id
        self.title = title
        self.minWidth = minWidth
        self.alignment = alignment
        self.isSortable = isSortable
        self.value = value
        self.cell = { AnyView(cell($0)) }
    }
}

/// Keeps a hierarchical table hierarchical while its columns sort.
///
/// Rows arrive as a flat list in display order: a section header (a group)
/// followed by the rows that belong to it. Without this, sorting a column would
/// interleave groups and their children; with it, the sorter orders sections by
/// their header value and sorts each section's children among themselves.
struct AppTableGrouping<Row> {
    let isSectionStart: (Row) -> Bool
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
    private let grouping: AppTableGrouping<Row>?
    private let onActivate: ((Row) -> Void)?
    @StateObject private var sorter: TableSorter<Row>
    @Environment(\.appTableDensity) private var density

    init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            resolvedSelection: nil, resolvedRowMenu: nil, grouping: nil, onActivate: nil)
    }

    /// A table whose rows can be selected and opened with a context menu.
    init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true,
        selection: Binding<Row.ID?>?
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            resolvedSelection: selection, resolvedRowMenu: nil, grouping: nil, onActivate: nil)
    }

    init<Menu: View>(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true,
        selection: Binding<Row.ID?>? = nil,
        @ViewBuilder rowMenu: @escaping (Row) -> Menu
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            resolvedSelection: selection, resolvedRowMenu: { AnyView(rowMenu($0)) },
            grouping: nil, onActivate: nil)
    }

    /// A hierarchical table: a click can expand a group, a right-click opens
    /// the row menu and the sorter keeps every child next to its group.
    init<Menu: View>(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool = true,
        selection: Binding<Row.ID?>? = nil,
        grouping: AppTableGrouping<Row>,
        onActivate: ((Row) -> Void)? = nil,
        @ViewBuilder rowMenu: @escaping (Row) -> Menu
    ) {
        self.init(
            columns: columns, rows: rows, initialKey: initialKey, ascending: ascending,
            resolvedSelection: selection, resolvedRowMenu: { AnyView(rowMenu($0)) },
            grouping: grouping, onActivate: onActivate)
    }

    /// The designated initializer. Its labels are deliberately different from
    /// the public ones: when it shared `selection:rowMenu:` with the generic
    /// view-builder overload, the compiler resolved the delegation above back
    /// to the generic initializer and every table with a row menu recursed
    /// until the stack overflowed.
    private init(
        columns: [AppTableColumn<Row>], rows: [Row], initialKey: String, ascending: Bool,
        resolvedSelection: Binding<Row.ID?>?, resolvedRowMenu: ((Row) -> AnyView)?,
        grouping: AppTableGrouping<Row>?, onActivate: ((Row) -> Void)?
    ) {
        self.columns = columns
        self.rows = rows
        self.selection = resolvedSelection
        self.rowMenu = resolvedRowMenu
        self.grouping = grouping
        self.onActivate = onActivate
        _sorter = StateObject(
            wrappedValue: TableSorter(
                columns: columns.filter(\.isSortable).map {
                    SortColumn(id: $0.id, title: $0.title, value: $0.value)
                },
                initialKey: initialKey,
                ascending: ascending))
    }

    var body: some View {
        // The table fills its card. A plain ScrollView proposes nil width to
        // its content, which made every row shrink to its intrinsic size and
        // left the card half empty; the reader supplies the width floor and
        // the ScrollView still takes over when the columns need more.
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                content
                    .frame(minWidth: proxy.size.width, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sortable table")
    }

    private var content: some View {
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

    private var sortedRows: [Row] {
        sorter.sorted(rows, grouping: grouping)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignToken.Spacing.medium) {
            ForEach(columns, id: \.id) { column in
                if column.isSortable {
                    Button {
                        if sorter.key == column.id {
                            sorter.ascending.toggle()
                        } else {
                            sorter.key = column.id
                            sorter.ascending = true
                        }
                    } label: {
                        headerLabel(column, showsDirection: true)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: column.minWidth, alignment: alignment(for: column))
                    .contentShape(Rectangle())
                    .help("Sort by \(column.title)")
                    .accessibilityLabel("Sort by \(column.title)")
                    .accessibilityValue(
                        sorter.key == column.id
                            ? (sorter.ascending ? "Ascending" : "Descending") : "")
                } else {
                    headerLabel(column, showsDirection: false)
                        .frame(minWidth: column.minWidth, alignment: alignment(for: column))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignToken.Spacing.tight)
    }

    private func headerLabel(
        _ column: AppTableColumn<Row>, showsDirection: Bool
    ) -> some View {
        let isSorted = showsDirection && sorter.key == column.id
        return HStack(spacing: 2) {
            Text(column.title)
            if isSorted {
                Image(systemName: sorter.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .font(.caption2.bold())
        .foregroundColor(isSorted ? .primary : .secondary)
        .lineLimit(1)
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
            onActivate?(row)
            guard let selection else { return }
            selection.wrappedValue = row.id
        }
        .contextMenu {
            if let rowMenu { rowMenu(row) }
        }
        .background(
            isSelected
                ? Color.accentColor.opacity(0.16)
                : (striped ? DesignToken.Surface.subtleFill : Color.clear),
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
