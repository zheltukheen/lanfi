import SwiftUI

/// The new top-level Wi-Fi workspace. It is the toolkit's selected home until
/// the full analyzer table is embedded here; the existing window stays the
/// detailed editor.
struct WiFiAnalyzerToolView: View {
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var survey: SurveyViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var showingSurvey = false
    @State private var showingSpectrum = false
    @State private var showingLiveCapture = false
    @State private var showingOfflineCapture = false
    @State private var showingRemoteSensors = false

    private var connected: NetworkModel? {
        analyzer.networks.first { $0.bssid == analyzer.currentConnectedBSSID }
    }

    private var topNetworks: [NetworkModel] {
        Array(analyzer.networks.sorted { $0.signal > $1.signal }.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                summary
                actions
                networks
            }
            .padding(18)
        }
        .sheet(isPresented: $showingSurvey) {
            SurveyView(analyzer: analyzer, survey: survey)
                .frame(minWidth: 1_000, minHeight: 700)
        }
        .sheet(isPresented: $showingSpectrum) {
            HardwareSpectrumView()
                .frame(minWidth: 980, minHeight: 620)
        }
        .sheet(isPresented: $showingLiveCapture) {
            LiveCaptureView(viewModel: analyzer)
        }
        .sheet(isPresented: $showingOfflineCapture) {
            OfflineCaptureView()
        }
        .sheet(isPresented: $showingRemoteSensors) {
            RemoteSensorsView()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wi-Fi Analyzer")
                    .font(.title2.bold())
                Text("Scan, quality, channels and the Wi-Fi tools that used to sit in the Tools menu.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open full analyzer", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            ToolkitStatusPill(text: scanStatus, tone: analyzer.networks.isEmpty ? .warning : .good)
        }
    }

    private var scanStatus: String {
        "\(analyzer.networks.count) networks · every \(String(format: "%.0f", analyzer.refreshInterval)) s"
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ToolkitCard {
                VStack(alignment: .leading, spacing: 4) {
                    ToolkitSectionLabel(text: "Connected")
                    if let connected {
                        Text(connected.displaySSID)
                            .font(.headline)
                        Text(
                            "\(connected.signal) dBm · \(connected.bandLabel) · ch \(connected.channel)"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text("Not connected")
                            .font(.headline)
                        Text("No active Wi-Fi association")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolkitCard {
                VStack(alignment: .leading, spacing: 4) {
                    ToolkitSectionLabel(text: "Quality")
                    if let connected,
                        let metrics = analyzer.metrics(for: connected)
                    {
                        Text("\(metrics.qualityScore)/100")
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundColor(metrics.qualityScore >= 70 ? .green : .orange)
                        Text("Signal, SNR, congestion and security")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("—")
                            .font(.title2)
                        Text("Select a connected network")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            ToolkitCard {
                VStack(alignment: .leading, spacing: 4) {
                    ToolkitSectionLabel(text: "5 GHz advice")
                    if let best = analyzer.analysis.bestChannel(for: .band5) {
                        Text("Channel \(best.channel)")
                            .font(.headline)
                        Text("\(best.widthMHz) MHz · \(best.rationale)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("—")
                            .font(.headline)
                        Text("Waiting for a scan")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolkitSectionLabel(text: "Wi-Fi tools")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                action(
                    "Site Survey", "Floor plan, samples and heatmap", "map",
                    action: { showingSurvey = true })
                action(
                    "Hardware Spectrum", "RF Explorer and CSV traces", "waveform.path.ecg",
                    action: { showingSpectrum = true })
                action(
                    "Live Capture", "PCAP with BPF filters", "record.circle",
                    action: { showingLiveCapture = true })
                action(
                    "Analyze Capture", "Offline pcap and pcapng", "doc.text.magnifyingglass",
                    action: { showingOfflineCapture = true })
                action(
                    "Remote Sensors", "Scan Macs over SSH", "antenna.radiowaves.left.and.right",
                    action: { showingRemoteSensors = true })
            }
        }
    }

    private func action(
        _ title: LocalizedStringKey,
        _ subtitle: LocalizedStringKey,
        _ icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var networks: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Networks")
                    Spacer()
                    Text("\(analyzer.networks.count) \(String(localized: "visible"))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if topNetworks.isEmpty {
                    Text("Waiting for the first scan…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    Table(topNetworks) {
                        TableColumn("Network") { network in
                            Text(network.displaySSID)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        TableColumn("Signal") { network in
                            Text("\(network.signal) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(network.signal > -60 ? .green : .orange)
                        }
                        .width(90)
                        TableColumn("Channel") { network in
                            Text("\(network.channel) · \(network.channelWidthMHz) MHz")
                                .font(.caption.monospacedDigit())
                        }
                        .width(110)
                        TableColumn("Security") { network in
                            Text(network.security)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .width(110)
                        TableColumn("Quality") { network in
                            Text("\(analyzer.metrics(for: network)?.qualityScore ?? 0)")
                                .font(.caption.monospacedDigit())
                        }
                        .width(70)
                    }
                    .frame(height: min(CGFloat(topNetworks.count) * 26 + 52, 300))
                }
                Text("The full analyzer table and inspectors will be embedded here in the next step.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }
}
