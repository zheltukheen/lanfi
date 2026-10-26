import SwiftUI

struct ExpressionColumnsSettingsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var columns: [ExpressionColumn] = []

    var body: some View {
        Form {
            Section("Custom expression columns") {
                Text(
                    "Tokens: {ssid} {bssid} {vendor} {signal} {noise} {snr} {channel} {band} {width} {security} {quality} {clients} {utilization} {generation} {apname}"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, _ in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            TextField("Column name", text: nameBinding(index))
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                let column = columns[index]
                                columns.remove(at: index)
                                viewModel.deleteExpressionColumn(column)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        TextField("Template, e.g. {ssid} · {signal} dBm", text: templateBinding(index))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { viewModel.updateExpressionColumn(columns[index]) }
                    }
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                Button {
                    let column = ExpressionColumn(id: UUID(), name: "Custom", template: "{ssid} · {signal} dBm")
                    columns.append(column)
                    viewModel.addExpressionColumn(name: column.name, template: column.template)
                } label: {
                    Label("Add expression column", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { columns = viewModel.expressionColumns }
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { columns[index].name },
            set: {
                columns[index].name = $0
                viewModel.updateExpressionColumn(columns[index])
            }
        )
    }

    private func templateBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { columns[index].template },
            set: {
                columns[index].template = $0
                viewModel.updateExpressionColumn(columns[index])
            }
        )
    }
}
