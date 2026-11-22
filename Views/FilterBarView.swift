import SwiftUI

/// Horizontal filter strip that lives in the main window's top row. It replaces
/// the old collapsible Filters sidebar: bands, signal threshold, sorting,
/// grouping, saved filter rules and per-value quick filters are all one row.
struct FilterBarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.lanFiHighContrast) private var highContrast
    @State private var showCategoryFilters = false
    @State private var showCustomFilters = false

    private struct SortOption: Identifiable {
        let column: ColumnId
        let title: String
        var id: String { column.rawValue }
    }

    /// Sort options follow the visible table columns in column order, minus the
    /// identity columns (see `ColumnId.isSortableOption`), so a new or renamed
    /// column shows up here without a second list to maintain.
    private var sortOptions: [SortOption] {
        viewModel.columnDefinitions
            .sorted { $0.order < $1.order }
            .filter { $0.isVisible }
            .compactMap { definition in
                guard let column = ColumnId(rawValue: definition.id), column.isSortableOption
                else { return nil }
                return SortOption(column: column, title: definition.displayTitle)
            }
    }

    private let signalPresets: [Double] = [-100, -90, -80, -70, -60, -50]

    var body: some View {
        HStack(spacing: 10) {
            bandChips
            Divider().frame(height: 20)
            signalMenu
            sortMenu
            groupMenu
            rulesMenu
            categoriesButton
            Spacer(minLength: 8)
            Text("\(viewModel.networks.count)/\(viewModel.totalNetworkCount)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .help("Visible networks / networks in the scan")
            clearButton
        }
        .padding(.horizontal, DesignToken.Spacing.medium)
        .padding(.vertical, DesignToken.Spacing.small)
        .background(Material.bar)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .bottom
        )
        .sheet(isPresented: $showCustomFilters) {
            CustomFiltersView(viewModel: viewModel)
        }
    }

    private var bandChips: some View {
        HStack(spacing: 8) {
            BandFilterChip(title: "2.4", color: .blue, isOn: $viewModel.filterBand24)
            BandFilterChip(title: "5", color: .purple, isOn: $viewModel.filterBand5)
            BandFilterChip(title: "6", color: .teal, isOn: $viewModel.filterBand6)
            BandFilterChip(title: "7", color: .green, isOn: $viewModel.filterWiFi7)
            BandFilterChip(title: "Other", color: .gray, isOn: $viewModel.filterOther)
        }
    }

    private var signalMenu: some View {
        Menu {
            ForEach(signalPresets, id: \.self) { value in
                Button {
                    viewModel.minSignalThreshold = value
                } label: {
                    if viewModel.minSignalThreshold == value {
                        Label(signalTitle(value), systemImage: "checkmark")
                    } else {
                        Text(signalTitle(value))
                    }
                }
            }
        } label: {
            AppMenuLabel(
                title: viewModel.minSignalThreshold <= -100
                    ? "Any signal" : "≥ \(Int(viewModel.minSignalThreshold)) dBm",
                systemImage: "cellularbars",
                isActive: viewModel.minSignalThreshold > -100)
        }
        .appMenuStyle()
        .help("Minimum signal")
    }

    private func signalTitle(_ value: Double) -> String {
        value <= -100 ? "Any signal" : "\(Int(value)) dBm"
    }

    private var sortMenu: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(sortOptions) { option in
                    Button {
                        viewModel.currentSortKey = option.column.rawValue
                    } label: {
                        if viewModel.currentSortKey == option.column.rawValue {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                AppMenuLabel(
                    title: sortTitle, systemImage: "arrow.up.arrow.down", isActive: true)
            }
            .appMenuStyle()

            Button {
                viewModel.isSortAscending.toggle()
            } label: {
                Image(systemName: viewModel.isSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help(viewModel.isSortAscending ? "Ascending" : "Descending")
            .accessibilityLabel(viewModel.isSortAscending ? "Sort ascending" : "Sort descending")
        }
    }

    private var sortTitle: String {
        if let key = viewModel.currentSortKey,
            let definition = viewModel.columnDefinitions.first(where: { $0.id == key })
        {
            return definition.displayTitle
        }
        return ColumnId.signal.defaultTitle
    }

    private var groupMenu: some View {
        Menu {
            ForEach(NetworkGroupMode.allCases) { mode in
                Button {
                    viewModel.groupMode = mode
                } label: {
                    if viewModel.groupMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            AppMenuLabel(
                title: viewModel.groupMode == .none ? "No grouping" : viewModel.groupMode.title,
                systemImage: "square.grid.2x2",
                isActive: viewModel.groupMode != .none)
        }
        .appMenuStyle()
        .help("Group networks")
    }

    private var rulesMenu: some View {
        Menu {
            Button("None") { viewModel.setActiveFilter(nil) }
            Divider()
            ForEach(viewModel.allFilters) { filter in
                Button {
                    viewModel.setActiveFilter(filter)
                } label: {
                    if viewModel.activeFilterId == filter.id {
                        Label(filter.name, systemImage: "checkmark")
                    } else {
                        Text(filter.name)
                    }
                }
            }
            Divider()
            Button("Edit custom filters…") { showCustomFilters = true }
        } label: {
            AppMenuLabel(
                title: viewModel.activeFilter?.name ?? "No rule",
                systemImage: "line.3.horizontal.decrease.circle",
                isActive: viewModel.activeFilter != nil)
        }
        .appMenuStyle()
        .help("Saved filter rules")
    }

    private var categoriesButton: some View {
        AppChip(
            title: String(localized: "Filters"),
            systemImage: "slider.horizontal.3",
            isOn: !viewModel.quickFilters.isEmpty,
            badge: viewModel.quickFilters.isEmpty ? nil : "\(viewModel.quickFilters.count)"
        ) {
            showCategoryFilters = true
        }
        .popover(isPresented: $showCategoryFilters, arrowEdge: .bottom) {
            categoryPopover
        }
        .help("Filter by channel, security, vendor and more")
    }

    private var categoryPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Quick Filters")
                        .font(.caption.bold())
                    Spacer()
                    Button("Manage…") { showCustomFilters = true }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
                if viewModel.filterColumns.isEmpty {
                    Text("Enable more columns to filter by them.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.filterColumns) { category in
                        FilterCategorySection(
                            column: category,
                            options: viewModel.sidebarOptions(for: category),
                            selection: Binding(
                                get: { viewModel.filterSelection(for: category) },
                                set: { viewModel.setFilterSelection($0, for: category) }
                            )
                        )
                    }
                }
            }
            .padding(DesignToken.Spacing.medium)
        }
        .frame(width: 320)
        .frame(maxHeight: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var clearButton: some View {
        Button {
            viewModel.clearAllFilters()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(viewModel.hasActiveFilters ? .secondary : .secondary.opacity(0.35))
        }
        .buttonStyle(.borderless)
        .disabled(!viewModel.hasActiveFilters)
        .help("Clear all filters")
        .accessibilityLabel("Clear all filters")
    }
}

private struct FilterCategorySection: View {
    let column: FilterColumn
    let options: [(value: String, count: Int)]
    @Binding var selection: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    Image(systemName: column.systemImage)
                        .font(.caption)
                        .foregroundColor(selection.isEmpty ? .secondary : .accentColor)
                        .frame(width: 15)
                    Text(column.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if !selection.isEmpty {
                        Text("\(selection.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.accentColor)
                    }
                }
                .padding(.vertical, DesignToken.Spacing.tight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 1) {
                    row("All", count: nil, isSelected: selection.isEmpty) {
                        selection.removeAll()
                    }
                    ForEach(options, id: \.value) { option in
                        row(option.value, count: option.count, isSelected: selection.contains(option.value)) {
                            if selection.contains(option.value) {
                                selection.remove(option.value)
                            } else {
                                selection.insert(option.value)
                            }
                        }
                    }
                }
                .padding(.leading, DesignToken.Spacing.sheet)
            }
        }
    }

    private func row(
        _ label: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.35))
                    .frame(width: 11)
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, DesignToken.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignToken.Radius.badge)
                    .fill(isSelected ? DesignToken.Surface.selectionFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
