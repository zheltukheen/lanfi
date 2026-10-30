import SwiftUI

struct CustomFiltersView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String?
    @State private var draft: CustomFilter?

    private var filters: [CustomFilter] { viewModel.allFilters }
    private var selected: CustomFilter? {
        guard let selectedId else { return nil }
        return filters.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom filters")
                        .font(.title3.bold())
                    Text("Combine field conditions with all/any logic, or apply automatic rules.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(14)
            Divider()

            HStack(spacing: 0) {
                sidebar.frame(width: 220)
                Divider()
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 760, height: 540)
        .onAppear {
            if selectedId == nil { selectedId = viewModel.activeFilterId ?? filters.first?.id }
            draft = selected
        }
        .onChange(of: selectedId) { _ in
            draft = selected.map { filter in
                var copy = filter
                copy.id = filter.isBuiltIn ? UUID().uuidString : filter.id
                return copy
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedId) {
                Section("Automatic") {
                    ForEach(filters.filter(\.isBuiltIn)) { filter in
                        Label(filter.name, systemImage: "bolt")
                            .tag(filter.id as String?)
                    }
                }
                Section("My filters") {
                    ForEach(filters.filter { !$0.isBuiltIn }) { filter in
                        Label(filter.name, systemImage: "line.3.horizontal.decrease.circle")
                            .tag(filter.id as String?)
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Button {
                    let newFilter = CustomFilter(
                        id: UUID().uuidString, name: "New filter", matchAll: true,
                        rules: [
                            NetworkFilterRule(field: .signal, op: .lessThan, value: "-75")
                        ])
                    viewModel.saveCustomFilter(newFilter)
                    selectedId = newFilter.id
                    draft = newFilter
                } label: {
                    Image(systemName: "plus")
                }
                .help("New filter")
                Spacer()
                if let selected, !selected.isBuiltIn {
                    Button(role: .destructive) {
                        viewModel.deleteCustomFilter(selected)
                        selectedId = nil
                        draft = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete filter")
                    .accessibilityLabel("Delete filter")
                }
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let filter = selected, let _ = draft {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(filter.name).font(.headline)
                        if filter.isBuiltIn {
                            Text("AUTOMATIC")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }

                    if filter.isBuiltIn {
                        Text("This rule is built in and cannot be edited.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ruleList(filter.rules, editable: false)
                    } else {
                        TextField("Filter name", text: binding(\.name))
                            .textFieldStyle(.roundedBorder)
                        Toggle("Match all rules (AND)", isOn: binding(\.matchAll))
                            .toggleStyle(.switch)
                        ruleList(draft?.rules ?? [], editable: true)
                        Button {
                            var rules = draft?.rules ?? []
                            rules.append(NetworkFilterRule(field: .ssid, op: .contains, value: ""))
                            draft?.rules = rules
                        } label: {
                            Label("Add condition", systemImage: "plus")
                        }
                        .controlSize(.small)
                    }

                    HStack {
                        Button("Apply") {
                            viewModel.setActiveFilter(filter)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        if filter.isBuiltIn == false {
                            Button("Save") {
                                if let draft { viewModel.saveCustomFilter(draft) }
                            }
                        }
                        Button("Clear active rule") {
                            viewModel.setActiveFilter(nil)
                            dismiss()
                        }
                        .disabled(viewModel.activeFilterId == nil)
                        Spacer()
                        if viewModel.activeFilterId == filter.id {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 38))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("Select or create a filter").font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func ruleList(_ rules: [NetworkFilterRule], editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rules) { rule in
                HStack(spacing: 6) {
                    if editable {
                        Picker("", selection: fieldBinding(rule.id)) {
                            ForEach(NetworkFilterField.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 135)
                        Picker("", selection: opBinding(rule.id)) {
                            ForEach(NetworkFilterOperator.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        TextField("Value", text: valueBinding(rule.id))
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            draft?.rules.removeAll { $0.id == rule.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove condition")
                    } else {
                        Text(rule.field.title).font(.caption.bold())
                        Text(rule.op.title).font(.caption).foregroundColor(.secondary)
                        Text(rule.value).font(.caption.monospaced())
                        Spacer()
                    }
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<CustomFilter, T>) -> Binding<T> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? selected![keyPath: keyPath] },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    private func fieldBinding(_ id: UUID) -> Binding<NetworkFilterField> {
        Binding(
            get: { draft?.rules.first { $0.id == id }?.field ?? .ssid },
            set: { value in
                if let index = draft?.rules.firstIndex(where: { $0.id == id }) { draft?.rules[index].field = value }
            }
        )
    }

    private func opBinding(_ id: UUID) -> Binding<NetworkFilterOperator> {
        Binding(
            get: { draft?.rules.first { $0.id == id }?.op ?? .equals },
            set: { value in
                if let index = draft?.rules.firstIndex(where: { $0.id == id }) { draft?.rules[index].op = value }
            }
        )
    }

    private func valueBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { draft?.rules.first { $0.id == id }?.value ?? "" },
            set: { value in
                if let index = draft?.rules.firstIndex(where: { $0.id == id }) { draft?.rules[index].value = value }
            }
        )
    }
}
