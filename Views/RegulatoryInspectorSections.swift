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

/// Inferred radios of the same physical access point. Shown only when the AP
/// does not advertise a name, so this never duplicates name grouping.
struct CoLocatedRadiosInspectorSection: View {
    let network: NetworkModel
    let siblings: [NetworkModel]
    var onSelect: (NetworkModel) -> Void = { _ in }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                if siblings.isEmpty {
                    Text(
                        "No other radios of this access point were inferred. LanFi merges radios only when an unnamed AP shares vendor, model and IE fingerprint across bands, and even then only one radio per band."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(siblings) { sibling in
                        Button {
                            onSelect(sibling)
                        } label: {
                            HStack(spacing: 6) {
                                Text(sibling.bandLabel)
                                    .font(.caption2)
                                    .frame(width: 48, alignment: .leading)
                                Text("Ch \(sibling.channel)")
                                    .font(.caption2)
                                    .frame(width: 62, alignment: .leading)
                                Text("\(sibling.signal) dBm")
                                    .font(.caption2.monospacedDigit())
                                    .frame(width: 56, alignment: .trailing)
                                Text(sibling.bssid.isEmpty ? "-" : sibling.bssid)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Select this radio")
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Same access point (inferred)", systemImage: "point.3.connected.trianglepath.dotted")
        }
    }
}

/// Plain-language reasons this BSSID can be hard to find: PSC, DFS, hidden
/// SSID. Complements the header tooltips with the network's actual values.
struct VisibilityInspectorSection: View {
    let network: NetworkModel

    private var advice: [VisibilityAdvice] {
        VisibilityAdvisor.advice(for: network)
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if advice.isEmpty {
                    Text(
                        "Nothing in this beacon limits discovery: no hidden SSID and no regulatory or scanning-channel caveat."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(advice) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: icon(for: item.kind))
                                    .font(.caption2)
                                    .foregroundColor(tint(for: item.kind))
                                Text(item.title).font(.caption.bold())
                            }
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Why it may be hard to see", systemImage: "eye.trianglebadge.exclamationmark")
        }
    }

    private func icon(for kind: VisibilityAdvice.Kind) -> String {
        switch kind {
        case .preferredScanning: return "checkmark.circle"
        case .notPreferredScanning: return "exclamationmark.circle"
        case .dfs: return "wave.3.right"
        case .hiddenSSID: return "eye.slash"
        }
    }

    private func tint(for kind: VisibilityAdvice.Kind) -> Color {
        switch kind {
        case .preferredScanning: return AppPalette.ok
        case .notPreferredScanning: return AppPalette.warning
        case .dfs: return AppPalette.info
        case .hiddenSSID: return AppPalette.warning
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
