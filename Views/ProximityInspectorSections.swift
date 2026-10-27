import SwiftUI

struct ProximityBeaconInspectorSection: View {
    let network: NetworkModel

    private var beacon: ProximityBeaconInfo? {
        ProximityBeaconInfo.find(in: network.informationElements)
    }

    var body: some View {
        GroupBox {
            if let beacon {
                VStack(alignment: .leading, spacing: 3) {
                    Label("iBeacon", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption.bold())
                    Text(beacon.uuid).font(.caption2.monospaced())
                    Text("Major \(beacon.major) · Minor \(beacon.minor) · TX \(beacon.txPower) dBm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            } else {
                Text("No iBeacon / proximity beacon advertised by this BSSID.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
        } label: {
            Label("Proximity beacon", systemImage: "dot.radiowaves.left.and.right")
        }
    }
}

struct ClientsInspectorSection: View {
    let network: NetworkModel
    @State private var showDiscovery = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if let clients = network.clients {
                    Label("\(clients) associated stations reported", systemImage: "person.3")
                        .font(.caption)
                } else {
                    Text("No client count in BSS Load.")
                        .font(.caption)
                }
                Text(
                    "Per-client MAC list requires a monitor-mode capture or AP telemetry; CoreWLAN does not expose it."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Label("Clients", systemImage: "person.3")
                Spacer()
                Button("Discover…") { showDiscovery = true }
                    .controlSize(.mini)
            }
        }
        .sheet(isPresented: $showDiscovery) {
            LiveClientDiscoveryView()
        }
    }
}
