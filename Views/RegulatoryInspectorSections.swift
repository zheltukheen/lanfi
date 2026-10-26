import SwiftUI

struct RegulatoryInspectorSection: View {
    let network: NetworkModel

    private var isDFS: Bool {
        guard network.band == .band5 || network.band == .band6 else { return false }
        return (52...144).contains(network.channel)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                fact("Country", network.countryCode ?? "Not advertised")
                fact("Channel", "\(network.channel) · \(network.channelWidthLabel) MHz")
                fact("DFS", isDFS ? "Yes" : "No")
                fact("6 GHz AFC", network.band == .band6 ? "Not exposed by CoreWLAN" : "Not applicable")
                fact("EHT / 320 MHz", network.generation == .mode11be ? "Wi-Fi 7 · EHT" : "Not advertised")
            }
            .padding(4)
        } label: {
            Label("Regulatory & 6 GHz", systemImage: "globe")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption2).lineLimit(1)
        }
    }
}

struct OtherRadiosInspectorSection: View {
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Label("Zigbee / Thread", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.bold())
                Text(
                    "Not visible to the built-in Wi-Fi radio. Requires a dedicated 802.15.4 adapter; LanFi does not emulate that data."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Other radios", systemImage: "dot.radiowaves.left.and.right")
        }
    }
}
