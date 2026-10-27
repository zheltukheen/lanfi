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

            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow {
                        ForEach(
                            [
                                "Network", "BSSID", "Band", "Ch", "Width", "Security",
                                "dBm", "Noise", "SNR", "Clients", "Util.", "Quality", "Generation",
                            ],
                            id: \.self
                        ) { title in
                            Text(title).font(.caption2.bold()).foregroundColor(.secondary)
                        }
                    }
                    Divider().gridCellColumns(13)
                    ForEach(selected) { network in
                        GridRow {
                            Text(network.displaySSID).font(.caption).lineLimit(1).frame(
                                minWidth: 110, alignment: .leading)
                            Text(network.bssid).font(.caption2.monospaced()).lineLimit(1)
                            Text(network.band.label).font(.caption2)
                            Text("\(network.channel)").font(.caption2)
                            Text(network.channelWidthLabel).font(.caption2)
                            Text(network.security).font(.caption2).lineLimit(1)
                            Text("\(network.signal)").font(.caption2)
                            Text(network.noise.map(String.init) ?? "—").font(.caption2)
                            Text(network.snr.map(String.init) ?? "—").font(.caption2)
                            Text(network.clients.map(String.init) ?? "—").font(.caption2)
                            Text(network.channelUtilization.map { "\($0)%" } ?? "—").font(.caption2)
                            Text("\(viewModel.metrics(for: network)?.qualityScore ?? 0)").font(.caption2)
                            Text(network.generation.label).font(.caption2)
                        }
                        Divider().gridCellColumns(13)
                    }
                }
                .padding(12)
            }
        }
    }
}
