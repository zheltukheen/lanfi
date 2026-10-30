import SwiftUI

struct ColorRulesSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var rules: [ColoringRule] = []

    var body: some View {
        Form {
            Section("Automatic row colors") {
                if rules.isEmpty {
                    Text("No coloring rules. Add a rule to tint rows automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    ruleEditor(index: index)
                }
                Button {
                    rules.append(
                        ColoringRule(
                            name: "New rule", field: .security, op: .contains,
                            value: "open", colorHex: "#FF6B6B"
                        )
                    )
                    save()
                } label: {
                    Label("Add coloring rule", systemImage: "plus")
                }
            }
            Section {
                Text("Rules apply in order. A manually selected row color always wins.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { rules = viewModel.coloringRules }
    }

    private func ruleEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("Rule name", text: binding(index, \.name))
                    .textFieldStyle(.roundedBorder)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(nsColor: ColorHex.color(from: rules[index].colorHex) ?? .orange) },
                        set: {
                            rules[index].colorHex = ColorHex.hex(from: NSColor($0))
                            save()
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 32)
                Toggle("", isOn: binding(index, \.isEnabled)).labelsHidden()
                Button(role: .destructive) {
                    rules.remove(at: index)
                    save()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete coloring rule")
                .buttonStyle(.borderless)
            }
            HStack(spacing: 6) {
                Picker("", selection: binding(index, \.field)) {
                    ForEach(NetworkFilterField.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                Picker("", selection: binding(index, \.op)) {
                    ForEach(NetworkFilterOperator.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 105)
                TextField("Value", text: binding(index, \.value))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { save() }
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func binding<T>(_ index: Int, _ keyPath: WritableKeyPath<ColoringRule, T>) -> Binding<T> {
        Binding(
            get: { rules[index][keyPath: keyPath] },
            set: {
                rules[index][keyPath: keyPath] = $0
                save()
            }
        )
    }

    private func save() {
        viewModel.saveColoringRules(rules)
    }
}
