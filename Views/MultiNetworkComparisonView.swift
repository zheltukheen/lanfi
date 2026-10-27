import SwiftUI

struct MultiNetworkComparisonView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        let selected = viewModel.selectedNetworks
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selected.count) networks selected")
                        .font(.headline)
                    Text("Side-by-side comparison of the current selection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Clear Selection") {
                    viewModel.setSelection(ids: [], primary: nil)
                }
                .controlSize(.small)
            }
            .padding(12)
            Divider()

            NetworkComparisonTable(viewModel: viewModel, networks: selected)

        }
    }
}
