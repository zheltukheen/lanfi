import SwiftUI

struct SidebarFilterView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.lanFiHighContrast) private var highContrast
    @State private var expandedSections: Set<FilterColumn> = []
    @State private var showSortPopover = false
    @State private var showCustomFilters = false

    private let sortOptions: [ColumnId] = [
        .signal, .quality, .networkName, .channel, .band, .security,
        .vendor, .lastSeen, .seen, .maxRate,
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sortCard
                    automaticRules
                    ForEach(viewModel.filterColumns) { category in
                        let options = viewModel.sidebarOptions(for: category)
                        let total = options.reduce(0) { $0 + $1.count }
                        SidebarSection(
                            title: category.title,
                            systemImage: category.systemImage,
                            options: options,
                            totalCount: total,
                            selection: binding(for: category),
                            isExpanded: Binding(
                                get: { expandedSections.contains(category) },
                                set: { expanded in
                                    if expanded {
                                        expandedSections.insert(category)
                                    } else {
                                        expandedSections.remove(category)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showCustomFilters) {
            CustomFiltersView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Filters")
                    .font(.headline)
                Text("\(viewModel.networks.count) visible networks")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                showCustomFilters = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderless)
            .help("Custom filters")
            Button {
                viewModel.clearAllFilters()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(viewModel.hasActiveFilters ? .secondary : .secondary.opacity(0.35))
            }
            .buttonStyle(.borderless)
            .help("Clear all filters")
            .disabled(!viewModel.hasActiveFilters)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var automaticRules: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rules").font(.caption.bold())
                Spacer()
                Button {
                    showCustomFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Edit custom filters")
            }
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
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(.accentColor)
                    Text(viewModel.activeFilter?.name ?? "No rule")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(highContrast ? 0.55 : 0.15), lineWidth: highContrast ? 2 : 1)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private var sortCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                Text("Sort by")
                    .font(.caption.bold())
                Spacer()
            }

            HStack(spacing: 6) {
                Button {
                    showSortPopover = true
                } label: {
                    HStack(spacing: 6) {
                        Text(
                            sortOptions.first { $0.rawValue == viewModel.currentSortKey }?.defaultTitle
                                ?? ColumnId.signal.defaultTitle
                        )
                        .font(.caption)
                        .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                Color.secondary.opacity(highContrast ? 0.55 : 0.15), lineWidth: highContrast ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .popover(isPresented: $showSortPopover, arrowEdge: .bottom) {
                    SortPopover(
                        options: sortOptions,
                        selection: Binding(
                            get: { viewModel.currentSortKey ?? ColumnId.signal.rawValue },
                            set: { viewModel.currentSortKey = $0 }
                        )
                    )
                }

                Button {
                    viewModel.isSortAscending.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: viewModel.isSortAscending ? "arrow.up" : "arrow.down")
                        Text(viewModel.isSortAscending ? "Asc" : "Desc")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(viewModel.isSortAscending ? "Ascending" : "Descending")
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    private func binding(for category: FilterColumn) -> Binding<Set<String>> {
        Binding(
            get: { viewModel.filterSelection(for: category) },
            set: { viewModel.setFilterSelection($0, for: category) }
        )
    }

}

struct SidebarSection: View {
    let title: String
    let systemImage: String
    let options: [(value: String, count: Int)]
    let totalCount: Int
    @Binding var selection: Set<String>
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    Image(systemName: systemImage)
                        .font(.caption.bold())
                        .foregroundColor(selection.isEmpty ? .secondary : .accentColor)
                        .frame(width: 16)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(totalCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.10)))
                    if !selection.isEmpty {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .contentShape(Rectangle())
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(spacing: 1) {
                    SidebarOptionRow(label: "All", count: totalCount, isSelected: selection.isEmpty) {
                        selection.removeAll()
                    }
                    ForEach(options, id: \.value) { option in
                        SidebarOptionRow(
                            label: option.value, count: option.count,
                            isSelected: selection.contains(option.value)
                        ) {
                            if selection.contains(option.value) {
                                selection.remove(option.value)
                            } else {
                                selection.insert(option.value)
                            }
                        }
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct SidebarOptionRow: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.35))
                    .frame(width: 12)
                Text(label)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12) : (hovering ? Color.secondary.opacity(0.07) : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SortPopover: View {
    let options: [ColumnId]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Sort networks by")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            ForEach(options, id: \.self) { option in
                SortOptionRow(
                    title: option.defaultTitle,
                    isSelected: option.rawValue == selection
                ) {
                    selection = option.rawValue
                    dismiss()
                }
            }
        }
        .padding(7)
        .frame(width: 230)
    }
}

private struct SortOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark" : "")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.accentColor)
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12) : (hovering ? Color.secondary.opacity(0.08) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
