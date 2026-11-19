import SwiftUI

/// Single comparison table used by both the side inspector and the bottom
/// Profile/Raw Data panels. Built with `AppTable`, so the header, sorting and
/// striping are the same as every other table in the app.
struct NetworkComparisonTable: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let networks: [NetworkModel]

    private func metric(_ text: String?) -> AnyView {
        AnyView(
            Text(text ?? "—")
                .font(.caption2)
                .lineLimit(1)
                .foregroundColor(text == nil ? .secondary : .primary)
        )
    }

    private func number(_ value: Int?) -> AnyView {
        metric(value.map(String.init))
    }

    private var columns: [AppTableColumn<NetworkModel>] {
        [
            AppTableColumn(
                id: "network", title: "Network", minWidth: 110,
                value: { .text($0.displaySSID) },
                cell: { network in
                    AnyView(
                        Text(network.displaySSID)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading))
                }),
            AppTableColumn(
                id: "bssid", title: "BSSID", minWidth: 120,
                value: { .text($0.bssid) },
                cell: { network in
                    AnyView(Text(network.bssid).font(.caption2.monospaced()).lineLimit(1))
                }),
            AppTableColumn(
                id: "band", title: "Band", minWidth: 44,
                value: { .text($0.band.label) },
                cell: { network in AnyView(Text(network.band.label).font(.caption2)) }),
            AppTableColumn(
                id: "channel", title: "Ch", minWidth: 36,
                value: { .number($0.channel) },
                cell: { network in AnyView(Text("\(network.channel)").font(.caption2)) }),
            AppTableColumn(
                id: "width", title: "Width", minWidth: 46,
                value: { .number($0.channelWidthMHz) },
                cell: { network in AnyView(Text(network.channelWidthLabel).font(.caption2)) }),
            AppTableColumn(
                id: "security", title: "Security", minWidth: 76,
                value: { .text($0.security) },
                cell: { network in
                    AnyView(Text(network.security).font(.caption2).lineLimit(1))
                }),
            AppTableColumn(
                id: "signal", title: "dBm", minWidth: 40,
                value: { .number($0.signal) },
                cell: { network in AnyView(Text("\(network.signal)").font(.caption2)) }),
            AppTableColumn(
                id: "noise", title: "Noise", minWidth: 44,
                value: { .number($0.noise) }, cell: { network in number(network.noise) }),
            AppTableColumn(
                id: "snr", title: "SNR", minWidth: 36,
                value: { .number($0.snr) }, cell: { network in number(network.snr) }),
            AppTableColumn(
                id: "clients", title: "Clients", minWidth: 52,
                value: { .number($0.clients) }, cell: { network in number(network.clients) }),
            AppTableColumn(
                id: "utilization", title: "Util.", minWidth: 44,
                value: { .number($0.channelUtilization) },
                cell: { network in
                    metric(network.channelUtilization.map { "\($0)%" })
                }),
            AppTableColumn(
                id: "quality", title: "Quality", minWidth: 52,
                value: { .number(viewModel.metrics(for: $0)?.qualityScore) },
                cell: { network in
                    number(viewModel.metrics(for: network)?.qualityScore)
                }),
            AppTableColumn(
                id: "generation", title: "Generation", minWidth: 70,
                value: { .text($0.generation.label) },
                cell: { network in
                    AnyView(Text(network.generation.label).font(.caption2))
                }),
        ]
    }

    var body: some View {
        AppTable(columns: columns, rows: networks, initialKey: "signal", ascending: false)
            .accessibilityLabel("Network comparison")
    }
}
