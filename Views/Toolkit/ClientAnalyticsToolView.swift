import AppKit
import SwiftUI

/// P1.3 Client analytics. Beacon client counts are always available; the
/// frame-level table needs a short monitor capture, which macOS often denies on
/// built-in adapters, so the screen works with either source alone.
struct ClientAnalyticsToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    @State private var observations: [ClientObservation] = []
    @State private var channelAirtime: [ChannelAirtimeEntry] = []

    @State private var isCapturing = false
    @State private var captureError: String?
    @State private var interfaces: [String] = []
    @State private var selectedInterface = "en0"
    @State private var selection: String?

    private var snapshot: ClientAnalyticsSnapshot {
        ClientAnalyticsSnapshot.build(
            networks: analyzer.networks, observations: observations,
            channelAirtime: channelAirtime)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                summary
                captureBar
                apTable
                if !channelAirtime.isEmpty {
                    channelAirtimeTable
                }
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
                    if !observations.isEmpty || !channelAirtime.isEmpty {
                        AppButton("Clear capture", tone: .quiet) {
                            observations = []
                            channelAirtime = []
                        }
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

    /// G7: who actually reserved the channel's airtime. Transmitter-side, so
    /// it answers "is the congestion mine?" without opening Wireshark.
    private var channelAirtimeTable: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                SectionLabel(text: "Channel airtime")
                Spacer()
                if channelAirtime.contains(where: \.isLegacy) {
                    Text("Legacy 802.11b present")
                        .font(.caption2.bold())
                        .foregroundColor(AppPalette.warning)
                }
            }
            AppTable(
                columns: [
                    AppTableColumn(
                        id: "ssid", title: "SSID", minWidth: 120,
                        value: { .text($0.ssid) }
                    ) { Text($0.ssid).lineLimit(1) },
                    AppTableColumn(
                        id: "bssid", title: "BSSID", minWidth: 140,
                        value: { .text($0.bssid) }
                    ) { Text($0.bssid).font(.caption.monospaced()) },
                    AppTableColumn(
                        id: "frames", title: "Frames", minWidth: 60,
                        value: { .number($0.frames) }
                    ) { Text("\($0.frames)").monospacedDigit() },
                    AppTableColumn(
                        id: "airtime", title: "Airtime", minWidth: 80,
                        value: { .number($0.airtimeMicroseconds) }
                    ) { Text("\($0.airtimeMilliseconds) ms").monospacedDigit() },
                    AppTableColumn(
                        id: "share", title: "Share", minWidth: 70,
                        value: { .number($0.share.map { Int(($0 * 100).rounded()) }) }
                    ) { row in
                        Text(row.share.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                            .monospacedDigit()
                            .foregroundColor((row.share ?? 0) >= 0.4 ? AppPalette.warning : .secondary)
                    },
                    AppTableColumn(
                        id: "legacy", title: "11b", minWidth: 50,
                        value: { .text($0.isLegacy ? "Yes" : "No") }
                    ) { row in
                        Text(row.isLegacy ? "Yes" : "—")
                            .foregroundColor(row.isLegacy ? AppPalette.warning : .secondary)
                            .help(
                                row.isLegacy
                                    ? "\(row.legacyFrames) directed data frames at 1–11 Mbit/s"
                                    : "No legacy-rate data frames")
                    },
                ],
                rows: snapshot.channelAirtime, initialKey: "airtime", ascending: false
            )
            .frame(height: ToolkitTableHeight.rows(snapshot.channelAirtime.count))
            .appTableSurface()
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
                        id: "retries", title: "Retries", minWidth: 80,
                        value: { column in
                            let rate =
                                column.frames > 0
                                ? Int((Double(column.retries) / Double(column.frames) * 100).rounded())
                                : 0
                            return .number(rate * 1000 + min(column.retries, 999))
                        }
                    ) { row in
                        Text(
                            row.frames > 0
                                ? "\(row.retries) (\(Int((Double(row.retries) / Double(row.frames) * 100).rounded()))%)"
                                : "—"
                        ).monospacedDigit()
                    },
                    AppTableColumn(
                        id: "airtime", title: "Airtime", minWidth: 80,
                        value: { .number($0.airtimeMicroseconds) }
                    ) { Text("\($0.airtimeMicroseconds / 1000) ms").monospacedDigit() },
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
        channelAirtime = []
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
                let (clients, airtime) = try await Task.detached(priority: .userInitiated) {
                    (try PcapAnalyzer.clients(data: data), try PcapAnalyzer.channelAirtime(data: data))
                }.value
                await MainActor.run {
                    isCapturing = false
                    channelAirtime = airtime
                    observations = clients.map { client in
                        ClientObservation(
                            mac: client.mac,
                            bssid: client.bssid,
                            vendor: OUIParser.vendor(for: client.mac),
                            rssi: client.rssi,
                            frames: client.frameCount,
                            probes: client.probeSSIDs,
                            retries: client.retryFrames,
                            airtimeMicroseconds: client.airtimeMicroseconds
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
