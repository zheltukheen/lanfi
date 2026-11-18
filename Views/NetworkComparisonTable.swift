import SwiftUI

/// Single comparison table used by both the side inspector and the bottom
/// Profile/Raw Data panels.
struct NetworkComparisonTable: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let networks: [NetworkModel]

    private enum SortKey: String, CaseIterable, Identifiable {
        case network, bssid, band, channel, width, security, signal, noise, snr, clients,
            utilization, quality, generation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .network: return "Network"
            case .bssid: return "BSSID"
            case .band: return "Band"
            case .channel: return "Ch"
            case .width: return "Width"
            case .security: return "Security"
            case .signal: return "dBm"
            case .noise: return "Noise"
            case .snr: return "SNR"
            case .clients: return "Clients"
            case .utilization: return "Util."
            case .quality: return "Quality"
            case .generation: return "Generation"
            }
        }
    }

    @State private var sortKey: SortKey = .signal
    @State private var ascending = false

    private var sortedNetworks: [NetworkModel] {
        let ordered = networks.sorted { (lhs: NetworkModel, rhs: NetworkModel) -> Bool in
            switch sortKey {
            case .network:
                return lhs.displaySSID.localizedStandardCompare(rhs.displaySSID)
                    == .orderedAscending
            case .bssid:
                return lhs.bssid.localizedStandardCompare(rhs.bssid) == .orderedAscending
            case .band: return lhs.band.rawValue < rhs.band.rawValue
            case .channel: return lhs.channel < rhs.channel
            case .width: return lhs.channelWidthMHz < rhs.channelWidthMHz
            case .security:
                return lhs.security.localizedStandardCompare(rhs.security) == .orderedAscending
            case .signal: return lhs.signal < rhs.signal
            case .noise: return (lhs.noise ?? Int.min) < (rhs.noise ?? Int.min)
            case .snr: return (lhs.snr ?? Int.min) < (rhs.snr ?? Int.min)
            case .clients: return (lhs.clients ?? Int.min) < (rhs.clients ?? Int.min)
            case .utilization:
                return (lhs.channelUtilization ?? Int.min) < (rhs.channelUtilization ?? Int.min)
            case .quality:
                return (viewModel.metrics(for: lhs)?.qualityScore ?? 0)
                    < (viewModel.metrics(for: rhs)?.qualityScore ?? 0)
            case .generation: return lhs.generation.sortOrder < rhs.generation.sortOrder
            }
        }
        return ascending ? ordered : ordered.reversed()
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    ForEach(SortKey.allCases) { key in
                        Button {
                            if sortKey == key {
                                ascending.toggle()
                            } else {
                                sortKey = key
                                ascending = key == .network || key == .bssid
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(key.title)
                                if sortKey == key {
                                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                                }
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Sort by \(key.title)")
                    }
                }
                Divider().gridCellColumns(SortKey.allCases.count)
                ForEach(sortedNetworks) { network in
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
                    Divider().gridCellColumns(SortKey.allCases.count)
                }
            }
            .padding(DesignToken.Spacing.tight)
        }
        .accessibilityLabel("Network comparison")
    }
}
