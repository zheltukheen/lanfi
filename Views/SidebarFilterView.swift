import SwiftUI

struct SidebarFilterView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var expandedSections: Set<SidebarCategory> = []

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
                    ForEach(SidebarCategory.allCases, id: \.self) { category in
                        let options = viewModel.sidebarOptions(for: category)
                        let total = options.reduce(0) { $0 + $1.count }
                        SidebarSection(
                            title: category.title,
                            systemImage: icon(for: category),
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
                viewModel.clearQuickFilters()
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
                Picker(
                    "Sort By",
                    selection: Binding(
                        get: { viewModel.currentSortKey ?? ColumnId.signal.rawValue },
                        set: { viewModel.currentSortKey = $0 }
                    )
                ) {
                    ForEach(sortOptions, id: \.self) { option in
                        Text(option.defaultTitle).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

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

    private func icon(for category: SidebarCategory) -> String {
        switch category {
        case .networkName: return "wifi"
        case .mode: return "dot.radiowaves.left.and.right"
        case .channel: return "waveform.path.ecg"
        case .channelWidth: return "arrow.left.and.right"
        case .security: return "lock.shield"
        case .accessPoint: return "antenna.radiowaves.left.and.right"
        case .vendor: return "building.2"
        }
    }

    private func binding(for category: SidebarCategory) -> Binding<String?> {
        switch category {
        case .networkName: return $viewModel.quickFilterNetworkName
        case .mode: return $viewModel.quickFilterMode
        case .channel: return $viewModel.quickFilterChannel
        case .channelWidth: return $viewModel.quickFilterChannelWidth
        case .security: return $viewModel.quickFilterSecurity
        case .accessPoint: return $viewModel.quickFilterAccessPoint
        case .vendor: return $viewModel.quickFilterVendor
        }
    }
}

struct SidebarSection: View {
    let title: String
    let systemImage: String
    let options: [(value: String, count: Int)]
    let totalCount: Int
    @Binding var selection: String?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 1) {
                SidebarOptionRow(label: "All", count: totalCount, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(options, id: \.value) { option in
                    SidebarOptionRow(label: option.value, count: option.count, isSelected: selection == option.value) {
                        selection = option.value
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.caption.bold())
                    .foregroundColor(selection == nil ? .secondary : .accentColor)
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
                if selection != nil {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disclosureGroupStyle(.automatic)
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
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
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
