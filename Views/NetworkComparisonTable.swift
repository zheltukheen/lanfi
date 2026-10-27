import SwiftUI

/// Single comparison table used by both the side inspector and the bottom
/// Profile/Raw Data panels.
struct NetworkComparisonTable: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let networks: [NetworkModel]

    private let titles = [
        "Network", "BSSID", "Band", "Ch", "Width", "Security",
        "dBm", "Noise", "SNR", "Clients", "Util.", "Quality", "Generation",
    ]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    ForEach(titles, id: \.self) { title in
                        Text(title).font(.caption2.bold()).foregroundColor(.secondary)
                    }
                }
                Divider().gridCellColumns(titles.count)
                ForEach(networks) { network in
                    GridRow {
                        Text(network.displaySSID).font(.caption).lineLimit(1).frame(minWidth: 110, alignment: .leading)
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
                    Divider().gridCellColumns(titles.count)
                }
            }
            .padding(6)
        }
        .accessibilityLabel("Network comparison")
    }
}
