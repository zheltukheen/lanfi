import SwiftUI

/// Connected-link telemetry block (P2.6). Values are sampled every 5 s; NSS is
/// derived from the beacon's spatial streams and labelled as a capability
/// because CoreWLAN does not expose MCS/NSS for the live link.
struct LinkInspectorSection: View {
    let network: NetworkModel

    @StateObject private var monitor = ConnectedLinkMonitor()

    private var summary: LinkTelemetrySummary { monitor.summary }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                    spacing: 8
                ) {
                    DetailRow(
                        label: "Rate",
                        value: LinkTelemetryPresentation.rate(monitor.rateMbps ?? summary.latest?.rateMbps))
                    DetailRow(label: "PHY", value: network.generationLabel)
                    DetailRow(
                        label: "Width",
                        value: LinkTelemetryPresentation.width(monitor.widthMHz))
                    DetailRow(
                        label: "Band / channel",
                        value: "\(network.bandLabel) · \(monitor.channel ?? network.channel)")
                    DetailRow(
                        label: "Streams",
                        value: LinkTelemetryPresentation.nssCapability(streams: network.streams))
                    DetailRow(
                        label: "Noise",
                        value: (monitor.noise ?? network.noise).map { "\($0) dBm" } ?? "—")
                }

                if let minimum = summary.rateMin, let maximum = summary.rateMax,
                    let average = summary.rateAverage
                {
                    Text(
                        "Rate over the last \(summary.sampleCount) samples: "
                            + String(format: "%.0f–%.0f Mbps (avg %.0f)", minimum, maximum, average)
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                } else {
                    Text("Collecting link samples every 5 s…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text("NSS is the beacon's capability, not a live measurement.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(4)
        } label: {
            Label("Link", systemImage: "antenna.radiowaves.left.and.right")
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
