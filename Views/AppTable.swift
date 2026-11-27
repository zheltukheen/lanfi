import AppKit
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
    /// Widths the user dragged by hand, keyed by column id. Columns without an
    /// entry share whatever width is left over, so a table always fills its
    /// card and a resized column never squeezes the others to nothing.
    @State private var columnOverrides: [String: CGFloat] = [:]
    /// Width of the column being dragged when the drag started; without it the
    /// width would feed back into itself and the column would run away.
    @State private var dragOrigin: CGFloat?

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

    @Environment(\.cardContentPadding) private var cardContentPadding

    var body: some View {
        // The table fills its card. A plain ScrollView proposes nil width to
        // its content, which let every column fall back to its minimum and
        // left the card half empty; the reader supplies the width floor and
        // the ScrollView still takes over once a column is dragged wider.
        GeometryReader { proxy in
            // Columns fill the whole card width: no horizontal padding around
            // the table itself, so a table never shows a gap between its card
            // edge and the first or last column. Each cell keeps its own inset.
            let widths = columnWidths(fitting: proxy.size.width)
            ScrollView([.horizontal, .vertical]) {
                table(widths: widths)
                    .frame(width: max(widths.reduce(0, +), 1), alignment: .leading)
                    .frame(minWidth: proxy.size.width, alignment: .leading)
            }
        }
        // A table inside a padded card reaches the card's side edges; the
        // cell inset still keeps text off the border.
        .padding(.horizontal, -cardContentPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sortable table")
    }

    private func table(widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(widths: widths)
            Divider()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sortedRows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, widths: widths, striped: index.isMultiple(of: 2))
                    Divider().opacity(0.35)
                }
            }
        }
        .padding(.bottom, DesignToken.Spacing.tight)
    }

    private var sortedRows: [Row] {
        sorter.sorted(rows, grouping: grouping)
    }

    /// Column widths for the space the card actually has; the rules live in
    /// `TableColumnLayout` so they can be checked without a window.
    private func columnWidths(fitting available: CGFloat) -> [CGFloat] {
        var overrides: [Int: CGFloat] = [:]
        for (index, column) in columns.enumerated() {
            if let width = columnOverrides[column.id] { overrides[index] = width }
        }
        return TableColumnLayout.widths(
            minimums: columns.map(\.minWidth),
            overrides: overrides,
            available: available
        )
    }

    private func header(widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                headerCell(column, width: widths[index], isLast: index == columns.count - 1)
            }
        }
        .frame(height: TableMetrics.headerHeight)
        .background(Theme.Surface.subtleFill)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Surface.divider)
                .frame(height: Theme.Stroke.hairline)
        }
    }

    private func headerCell(
        _ column: AppTableColumn<Row>, width: CGFloat, isLast: Bool
    ) -> some View {
        let content = headerLabel(column, showsDirection: column.isSortable)
            .padding(.horizontal, TableMetrics.cellInset)
            .frame(width: width, alignment: alignment(for: column))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())

        return Group {
            if column.isSortable {
                Button {
                    if sorter.key == column.id {
                        sorter.ascending.toggle()
                    } else {
                        sorter.key = column.id
                        sorter.ascending = true
                    }
                } label: {
                    content
                }
                .buttonStyle(.plain)
                .help("Sort by \(column.title)")
                .accessibilityLabel("Sort by \(column.title)")
                .accessibilityValue(
                    sorter.key == column.id
                        ? (sorter.ascending ? "Ascending" : "Descending") : "")
            } else {
                content
            }
        }
        .overlay(alignment: .trailing) {
            if !isLast {
                columnSeparator
            }
        }
        .overlay(alignment: .trailing) {
            resizeHandle(for: column, width: width)
        }
    }

    private func headerLabel(
        _ column: AppTableColumn<Row>, showsDirection: Bool
    ) -> some View {
        let isSorted = showsDirection && sorter.key == column.id
        return HStack(spacing: DesignToken.Spacing.hairline) {
            // Column titles are plain strings, and a call site that writes a
            // literal there is invisible to `String(localized:)`. Resolving the
            // title as a localized key at the one place headers are drawn makes
            // every table translate without touching each column list; a title
            // that is already translated simply falls back to itself.
            Text(LocalizedStringKey(column.title))
            if isSorted {
                Image(systemName: sorter.ascending ? "chevron.up" : "chevron.down")
                    .font(Theme.Typography.chevron)
            }
        }
        .font(Theme.Typography.tableHeader)
        .foregroundColor(isSorted ? .primary : .secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// The hairline between two columns. It runs the full height of the row it
    /// belongs to, which is why cells carry their own vertical padding.
    private var columnSeparator: some View {
        Rectangle()
            .fill(Theme.Surface.divider)
            .frame(width: Theme.Stroke.hairline)
            .frame(maxHeight: .infinity)
    }

    /// A grab strip on the column's trailing edge. It sits above the header
    /// button: a drag resizes, a plain click still sorts.
    private func resizeHandle(for column: AppTableColumn<Row>, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: TableMetrics.resizeHandleWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragOrigin == nil { dragOrigin = width }
                        let start = dragOrigin ?? width
                        columnOverrides[column.id] = max(
                            TableMetrics.minColumnWidth, start + value.translation.width)
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
            .help("Drag to resize")
            .accessibilityLabel("Resize \(column.title)")
    }

    private func rowView(_ row: Row, widths: [CGFloat], striped: Bool) -> some View {
        let isSelected = selection?.wrappedValue == row.id
        let verticalInset = max(2, (density.rowHeight - 18) / 2)
        return HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                column.cell(row)
                    .padding(.horizontal, TableMetrics.cellInset)
                    .padding(.vertical, verticalInset)
                    .frame(width: widths[index], alignment: alignment(for: column))
                    .overlay(alignment: .trailing) {
                        if index < columns.count - 1 {
                            columnSeparator
                        }
                    }
            }
        }
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
                ? Theme.Surface.selectionFill
                : (striped ? DesignToken.Surface.subtleFill : Color.clear)
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
