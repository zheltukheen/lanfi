import AppKit
import SwiftUI

/// P1.3 Client analytics. Beacon client counts are always available; the
/// frame-level table needs a short monitor capture, which macOS often denies on
/// built-in adapters, so the screen works with either source alone.
struct ClientAnalyticsToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    @State private var observations: [ClientObservation] = []

    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var interfaces: [String] = []
    @State private var selectedInterface = "en0"
    @State private var selection: String?

    private var snapshot: ClientAnalyticsSnapshot {
        ClientAnalyticsSnapshot.build(networks: analyzer.networks, observations: observations)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                summary
                captureBar
                apTable
                if !observations.isEmpty {
                    clientTable
                }
                insights
            }
            .appContentPadding()
        }
        .onAppear {
            interfaces = LiveCaptureService.interfaceNames()
            if interfaces.contains("en0") {
                selectedInterface = "en0"
            } else if let first = interfaces.first {
                selectedInterface = first
            }
        }
    }

    private var summary: some View {
        HStack(spacing: DesignToken.Spacing.medium) {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Advertised clients")
                    HStack(spacing: DesignToken.Spacing.large) {
                        StatTile(
                            value: "\(snapshot.advertisedClients)", label: "Across APs")
                        StatTile(
                            value: "\(snapshot.busiestAccessPoints.count)",
                            label: "Reporting APs", tint: AppPalette.info)
                        StatTile(
                            value: "\(snapshot.idleAccessPoints)", label: "Silent APs",
                            tint: AppPalette.muted)
                    }
                }
            }
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    SectionLabel(text: "Captured frames")
                    HStack(spacing: DesignToken.Spacing.large) {
                        StatTile(
                            value: "\(snapshot.capturedClients)", label: "Unique clients",
                            tint: AppPalette.ok)
                        StatTile(value: "\(snapshot.capturedFrames)", label: "Frames")
                        StatTile(
                            value: snapshot.averageCapturedRSSI.map { "\($0) dBm" } ?? "—",
                            label: "Avg RSSI", tint: AppPalette.warning)
                    }
                }
            }
        }
    }

    private var captureBar: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    Picker("Interface", selection: $selectedInterface) {
                        ForEach(interfaces, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: DesignToken.Layout.controlWidthSmall + 60)
                    AppButton(
                        isCapturing ? "Capturing…" : "Capture 10 s of client frames",
                        systemImage: "dot.radiowaves.left.and.right", tone: .primary,
                        isBusy: isCapturing, isEnabled: !isCapturing && !interfaces.isEmpty
                    ) {
                        capture()
                    }
                    Spacer()
                    if !observations.isEmpty {
                        AppButton("Clear capture", tone: .quiet) { observations = [] }
                    }
                }
                Text(
                    "Beacon client counts need no permission. Frame-level clients need monitor mode; built-in Apple adapters frequently return no frames, so an external adapter is the reliable path."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let captureError {
                    Text(captureError).font(.caption).foregroundColor(AppPalette.danger)
                }
            }
        }
    }

    @ViewBuilder
    private var apTable: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                SectionLabel(text: "Access point load")
                Spacer()
            }
            if snapshot.busiestAccessPoints.isEmpty {
                Text("No access point advertised a client count in this scan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appContentPadding()
                    .appTableSurface()
            } else {
                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "ssid", title: "SSID", minWidth: 120,
                            value: { .text($0.ssid) }
                        ) { Text($0.ssid) },
                        AppTableColumn(
                            id: "bssid", title: "BSSID", minWidth: 140,
                            value: { .text($0.bssid) }
                        ) { Text($0.bssid).font(.caption.monospaced()) },
                        AppTableColumn(
                            id: "band", title: "Band", minWidth: 60,
                            value: { .text($0.band) }
                        ) { Text($0.band) },
                        AppTableColumn(
                            id: "channel", title: "Ch", minWidth: 44,
                            value: { .number($0.channel) }
                        ) { Text("\($0.channel)").monospacedDigit() },
                        AppTableColumn(
                            id: "clients", title: "Clients", minWidth: 100,
                            value: { .number($0.clients) }
                        ) { row in
                            HStack(spacing: DesignToken.Spacing.tight) {
                                Text("\(row.clients)").monospacedDigit().bold()
                                ProgressView(
                                    value: Double(min(row.clients, 30)), total: 30
                                )
                                .progressViewStyle(.linear)
                                .frame(width: 46)
                            }
                        },
                        AppTableColumn(
                            id: "utilization", title: "Util", minWidth: 50,
                            value: { .number($0.utilization) }
                        ) { row in
                            Text(row.utilization.map { "\($0)%" } ?? "—")
                                .monospacedDigit()
                                .foregroundColor(
                                    (row.utilization ?? 0) >= 60
                                        ? AppPalette.warning : .secondary)
                        },
                        AppTableColumn(
                            id: "signal", title: "RSSI", minWidth: 80,
                            value: { .number($0.signal) }
                        ) { Text("\($0.signal) dBm").monospacedDigit() },
                    ],
                    rows: snapshot.busiestAccessPoints, initialKey: "clients",
                    ascending: false
                )
                .frame(height: ToolkitTableHeight.rows(snapshot.busiestAccessPoints.count))
                .appTableSurface()
            }
        }
    }

    private var clientTable: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                SectionLabel(text: "Captured clients")
                Spacer()
            }
            AppTable(
                columns: [
                    AppTableColumn(
                        id: "mac", title: "MAC", minWidth: 120,
                        value: { .text($0.mac) }
                    ) { Text($0.mac).font(.caption.monospaced()) },
                    AppTableColumn(
                        id: "vendor", title: "Vendor", minWidth: 140,
                        value: { .text($0.vendor) }
                    ) { Text($0.vendor).font(.caption2) },
                    AppTableColumn(
                        id: "bssid", title: "BSSID", minWidth: 140,
                        value: { .text($0.bssid) }
                    ) { Text($0.bssid).font(.caption.monospaced()) },
                    AppTableColumn(
                        id: "frames", title: "Frames", minWidth: 60,
                        value: { .number($0.frames) }
                    ) { Text("\($0.frames)").monospacedDigit() },
                    AppTableColumn(
                        id: "rssi", title: "RSSI", minWidth: 70,
                        value: { .number($0.rssi) }
                    ) { Text($0.rssi.map { "\($0) dBm" } ?? "—") },
                    AppTableColumn(
                        id: "probes", title: "Probes", minWidth: 140,
                        value: { .text($0.probes.joined(separator: ", ")) }
                    ) { row in
                        Text(row.probes.isEmpty ? "—" : row.probes.joined(separator: ", "))
                            .lineLimit(1)
                            .help(row.probes.joined(separator: "\n"))
                    },
                ],
                rows: observations, initialKey: "frames", ascending: false,
                selection: $selection
            )
            .frame(height: ToolkitTableHeight.rows(observations.count))
            .appTableSurface()
        }
    }

    private var insights: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "What this means")
                ForEach(Array(snapshot.insights.enumerated()), id: \.offset) { _, insight in
                    HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(AppPalette.info)
                        Text(insight)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                if snapshot.insights.isEmpty {
                    Text("Client counts look normal for this scan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureError = nil
        observations = []
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-analytics-\(UUID().uuidString).pcap")
        let options = LiveCaptureOptions(
            interfaceName: selectedInterface, duration: 10, outputURL: url, monitorMode: true)
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try await LiveCaptureService.capture(options)
                }.value
                let data = try PcapAnalyzer.mappedData(at: url)
                let clients = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.clients(data: data)
                }.value
                await MainActor.run {
                    isCapturing = false
                    observations = clients.map { client in
                        ClientObservation(
                            mac: client.mac,
                            bssid: client.bssid,
                            vendor: OUIParser.vendor(for: client.mac),
                            rssi: client.rssi,
                            frames: client.frameCount,
                            probes: client.probeSSIDs
                        )
                    }
                    if observations.isEmpty {
                        captureError =
                            "Capture contained no client frames. Try an external adapter in monitor mode."
                    }
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                    captureError = error.localizedDescription
                }
            }
        }
    }
}
