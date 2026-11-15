import AppKit
import SwiftUI

struct NetworkInspectorView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Network Details").font(.headline)
                Spacer()
            }
            .padding()
            .background(Material.bar)

            Divider()

            ScrollView {
                if viewModel.selectedNetworkIds.count > 1 {
                    MultiSelectionInspector(viewModel: viewModel)
                } else if let network = viewModel.selectedNetwork {
                    VStack(alignment: .leading, spacing: 12) {

                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.displayName(for: network))
                                    .font(.title2).bold()
                                    .foregroundColor(
                                        network.bssid == viewModel.currentConnectedBSSID ? .accentColor : .primary
                                    )
                                    .lineLimit(2)

                                HStack {
                                    Text(network.bssid.isEmpty ? "-" : network.bssid)
                                        .font(.caption).monospaced()
                                        .padding(4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textSelection(.enabled)

                                    if network.bssid == viewModel.currentConnectedBSSID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .help("Currently Connected")
                                    }
                                }
                            }
                            Spacer()
                            SignalBadge(
                                rssi: network.signal,
                                label: viewModel.formatSignal(network.signal),
                                unit: viewModel.signalDisplayMode == .dbm ? "dBm" : ""
                            )
                        }

                        Divider()

                        // Quality, issues, history and utilization
                        if let metrics = viewModel.metrics(for: network) {
                            IssuesInspectorSection(network: network, metrics: metrics)
                            QualityInspectorSection(
                                metrics: metrics,
                                recommendation: viewModel.analysis.bestChannel(for: network.band)
                            )
                            if let advice = viewModel.channelAdvice(for: network) {
                                ChannelAdviceSection(advice: advice)
                            }
                            HistoryInspectorSection(network: network, viewModel: viewModel)
                            UtilizationInspectorSection(network: network, viewModel: viewModel)
                            ProximityBeaconInspectorSection(network: network)
                            ClientsInspectorSection(network: network)
                            MLOInspectorSection(network: network)
                            RegulatoryInspectorSection(network: network)
                            OtherRadiosInspectorSection()
                        }

                        GroupBox("Label & Notes") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(
                                    "Alias",
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).alias },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.alias = value
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                TextField(
                                    "Tags (comma separated)",
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).tags.joined(separator: ", ") },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.tags =
                                                value
                                                .split(separator: ",")
                                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                .filter { !$0.isEmpty }
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                TextEditor(
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).notes },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.notes = value
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .font(.caption)
                                .frame(minHeight: 44, maxHeight: 70)
                                .scrollContentBackground(.hidden)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                                HStack(spacing: 8) {
                                    Text("Row color").font(.caption)
                                    ColorPicker(
                                        "",
                                        selection: Binding(
                                            get: {
                                                Color(
                                                    nsColor: ColorHex.color(
                                                        from: viewModel.annotation(for: network).colorHex ?? ""
                                                    ) ?? .clear
                                                )
                                            },
                                            set: { value in
                                                viewModel.setNetworkColor(
                                                    ColorHex.hex(from: NSColor(value)), for: network
                                                )
                                            }
                                        ),
                                        supportsOpacity: false
                                    )
                                    .labelsHidden()
                                    .frame(width: 34)
                                    Button("Clear") {
                                        viewModel.setNetworkColor("", for: network)
                                    }
                                    .controlSize(.mini)
                                }

                                Text("Saved locally on this Mac")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }

                        // Specs
                        GroupBox("Technical Specs") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "Channel", value: "\(network.channel)")
                                DetailRow(label: "Band", value: network.bandLabel)
                                DetailRow(
                                    label: "Width",
                                    value: network.channelWidthLabel == "-" ? "-" : "\(network.channelWidthLabel) MHz")
                                DetailRow(label: "Generation", value: network.generationLabel)
                                DetailRow(
                                    label: "Max Rate",
                                    value: network.maxRateLabel == "-" ? "-" : "\(network.maxRateLabel) Mbps")
                                DetailRow(label: "Vendor", value: network.vendor)
                                DetailRow(label: "Mode", value: network.mode)
                                if let noise = network.noise {
                                    DetailRow(label: "Noise", value: "\(noise) dBm")
                                }
                                if let snr = network.snr {
                                    DetailRow(label: "SNR", value: "\(snr) dB")
                                }

                                // Безопасное разворачивание
                                DetailRow(label: "Streams", value: network.streams.map { "\($0)" } ?? "-")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                        // Security
                        GroupBox("Security & Advanced") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "Protocol", value: network.security)
                                DetailRow(label: "Protection Mode", value: network.protectionMode ?? "Unknown")
                                DetailRow(label: "WPS", value: network.wps ?? "N/A")
                                DetailRow(
                                    label: "Fast Transition (802.11r)",
                                    value: network.fastTransition == true ? "Yes" : "No")
                                if let beacon = network.beaconInterval {
                                    DetailRow(label: "Beacon Interval", value: "\(beacon) ms")
                                }
                                if let cc = network.countryCode {
                                    DetailRow(label: "Country Code", value: cc)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                        // Timestamps
                        GroupBox("Activity") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "First Seen", value: formatDate(network.firstSeen))
                                DetailRow(label: "Last Seen", value: formatDate(network.lastSeen))
                                DetailRow(label: "Seen Ago", value: "\(network.seen) sec")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                    }
                    .padding()
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("Select a network to view details")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
