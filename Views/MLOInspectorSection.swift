import SwiftUI

struct MLOInspectorSection: View {
    let network: NetworkModel

    private var info: MLOInfo? {
        MLOInfo.parse(elements: network.informationElements, widthMHz: network.channelWidthMHz)
    }

    var body: some View {
        GroupBox {
            if let info {
                VStack(alignment: .leading, spacing: 5) {
                    if let apMLD = info.apMLD {
                        fact("AP MLD", apMLD)
                    }
                    ForEach(info.links) { link in
                        HStack {
                            Text("Link \(link.linkID)").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text(link.bssid ?? "BSSID not advertised").font(.caption2.monospaced())
                        }
                    }
                    if info.links.isEmpty {
                        Text("Link IDs present, no per-link BSSID in the captured IE.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    fact("320 MHz", info.is320MHz ? "Yes" : "No")
                }
                .padding(4)
            } else {
                Text("No Multi-Link element for this BSSID. Capture a Wi-Fi 7 beacon to see link sets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(4)
            }
        } label: {
            Label("Wi-Fi 7 / MLO", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption2.monospaced()).lineLimit(1)
        }
    }
}
