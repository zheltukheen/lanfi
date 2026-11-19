import SwiftUI

/// Single comparison table used by both the side inspector and the bottom
/// Profile/Raw Data panels. Built with `AppTable`, so the header, sorting and
/// striping are the same as every other table in the app.
struct NetworkComparisonTable: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let networks: [NetworkModel]

    var body: some View {
        AppTable(columns: columns, rows: networks, initialKey: "signal", ascending: false)
            .accessibilityLabel("Network comparison")
    }

    private var columns: [AppTableColumn<NetworkModel>] {
        [
            AppTableColumn(
                id: "network", title: "Network", minWidth: 110,
                value: { .text($0.displaySSID) }
            ) { network in
                Text(network.displaySSID)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            },
            AppTableColumn(
                id: "bssid", title: "BSSID", minWidth: 120,
                value: { .text($0.bssid) }
            ) { network in
                Text(network.bssid).font(.caption2.monospaced()).lineLimit(1)
            },
            AppTableColumn(id: "band", title: "Band", minWidth: 44, value: { .text($0.band.label) }) {
                network in
                Text(network.band.label).font(.caption2)
            },
            AppTableColumn(
                id: "channel", title: "Ch", minWidth: 36, value: { .number($0.channel) }
            ) { network in
                Text("\(network.channel)").font(.caption2)
            },
            AppTableColumn(
                id: "width", title: "Width", minWidth: 46, value: { .number($0.channelWidthMHz) }
            ) { network in
                Text(network.channelWidthLabel).font(.caption2)
            },
            AppTableColumn(
                id: "security", title: "Security", minWidth: 76, value: { .text($0.security) }
            ) { network in
                Text(network.security).font(.caption2).lineLimit(1)
            },
            AppTableColumn(
                id: "signal", title: "dBm", minWidth: 40, value: { .number($0.signal) }
            ) { network in
                Text("\(network.signal)").font(.caption2)
            },
            AppTableColumn(id: "noise", title: "Noise", minWidth: 44, value: { .number($0.noise) }) {
                network in
                MetricText(network.noise.map(String.init))
            },
            AppTableColumn(id: "snr", title: "SNR", minWidth: 36, value: { .number($0.snr) }) {
                network in
                MetricText(network.snr.map(String.init))
            },
            AppTableColumn(
                id: "clients", title: "Clients", minWidth: 52, value: { .number($0.clients) }
            ) { network in
                MetricText(network.clients.map(String.init))
            },
            AppTableColumn(
                id: "utilization", title: "Util.", minWidth: 44,
                value: { .number($0.channelUtilization) }
            ) { network in
                MetricText(network.channelUtilization.map { "\($0)%" })
            },
            AppTableColumn(
                id: "quality", title: "Quality", minWidth: 52,
                value: { .number(viewModel.metrics(for: $0)?.qualityScore) }
            ) { network in
                MetricText(viewModel.metrics(for: network).map { String($0.qualityScore) })
            },
            AppTableColumn(
                id: "generation", title: "Generation", minWidth: 70,
                value: { .text($0.generation.label) }
            ) { network in
                Text(network.generation.label).font(.caption2)
            },
        ]
    }
}

/// A caption-sized value that greys out when the scan did not report it.
private struct MetricText: View {
    let text: String?

    init(_ text: String?) {
        self.text = text
    }

    var body: some View {
        Text(text ?? "—")
            .font(.caption2)
            .lineLimit(1)
            .foregroundColor(text == nil ? .secondary : .primary)
    }
}
