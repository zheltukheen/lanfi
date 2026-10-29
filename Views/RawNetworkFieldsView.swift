import SwiftUI

struct RawNetworkFieldsView: View {
    let network: NetworkModel

    private var fields: [(String, String)] {
        [
            ("SSID", network.ssid),
            ("Display SSID", network.displaySSID),
            ("BSSID", network.bssid),
            ("Band", network.band.label),
            ("Channel", "\(network.channel)"),
            ("Width", "\(network.channelWidthMHz) MHz"),
            ("Generation", network.generation.label),
            ("Security", network.security),
            ("Vendor", network.vendor),
            ("AP name", network.apName ?? "—"),
            ("Mode", network.mode),
            ("Signal", "\(network.signal) dBm"),
            ("Noise", network.noise.map { "\($0) dBm" } ?? "—"),
            ("SNR", network.snr.map(String.init) ?? "—"),
            ("Basic rates", (network.basicRates ?? []).map { "\($0)" }.joined(separator: ", ")),
            ("Min basic rate", "\(network.minBasicRate)"),
            ("Max basic rate", "\(network.maxBasicRate)"),
            ("Min rate", "\(network.minRate)"),
            ("Max rate", "\(network.maxRate)"),
            ("Center frequency", network.centerFrequency.map { "\($0) MHz" } ?? "—"),
            ("Utilization", network.channelUtilization.map { "\($0)%" } ?? "—"),
            ("Beacon interval", network.beaconInterval.map { "\($0) TU" } ?? "—"),
            ("Beacon rate", network.beaconRate.map { "\($0) Mbps" } ?? "—"),
            ("Beacon airtime", network.beaconAirtime.map { String(format: "%.2f ms", $0) } ?? "—"),
            ("Clients", network.clients.map(String.init) ?? "—"),
            ("Stations", network.stations.map(String.init) ?? "—"),
            ("Streams", network.streams.map(String.init) ?? "—"),
            ("Country", network.countryCode ?? "—"),
            ("Fast transition", network.fastTransition.map(String.init) ?? "—"),
            ("Protection", network.protectionMode ?? "—"),
            ("WPS", network.wps ?? "—"),
            ("WPS enabled", network.wpsEnabled.map(String.init) ?? "—"),
            ("PMF required", network.pmfRequired.map(String.init) ?? "—"),
            ("IE count", "\(network.ieCount)"),
            ("IE bytes", network.ieTotalLength.map(String.init) ?? "—"),
            ("First seen", network.firstSeen?.formatted(date: .abbreviated, time: .standard) ?? "—"),
            ("Last seen", network.lastSeen?.formatted(date: .abbreviated, time: .standard) ?? "—"),
            ("Seen count", "\(network.count)"),
        ]
    }

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                ForEach(fields, id: \.0) { key, value in
                    GridRow {
                        Text(key).font(.caption2).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
                        Text(value).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                    Divider().gridCellColumns(2)
                }
            }
            .padding(12)
        }
    }
}
