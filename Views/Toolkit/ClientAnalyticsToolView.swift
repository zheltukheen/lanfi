import AppKit
import SwiftUI

/// P1.3 Client analytics. Beacon client counts are always available; the
/// frame-level table needs a short monitor capture, which macOS often denies on
/// built-in adapters, so the screen works with either source alone.
struct ClientAnalyticsToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    @State private var observations: [ClientObservation] = []

    private enum APSortKey: String, CaseIterable, Identifiable {
        case ssid, bssid, band, channel, clients, utilization, signal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ssid: return String(localized: "SSID")
            case .bssid: return String(localized: "BSSID")
            case .band: return String(localized: "Band")
            case .channel: return String(localized: "Ch")
            case .clients: return String(localized: "Clients")
            case .utilization: return String(localized: "Util")
            case .signal: return String(localized: "RSSI")
            }
        }
    }

    private enum ClientSortKey: String, CaseIterable, Identifiable {
        case mac, vendor, bssid, frames, rssi, probes
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mac: return String(localized: "MAC")
            case .vendor: return String(localized: "Vendor")
            case .bssid: return String(localized: "BSSID")
            case .frames: return String(localized: "Frames")
            case .rssi: return String(localized: "RSSI")
            case .probes: return String(localized: "Probes")
            }
        }
    }

    @State private var apSortKey: APSortKey = .clients
    @State private var apAscending = false
    @State private var clientSortKey: ClientSortKey = .frames
    @State private var clientAscending = false

    private func sortedAccessPoints(
        _ rows: [ClientAnalyticsSnapshot.AccessPointLoad]
    ) -> [ClientAnalyticsSnapshot.AccessPointLoad] {
        let ordered = rows.sorted { lhs, rhs in
            switch apSortKey {
            case .ssid: return lhs.ssid.localizedStandardCompare(rhs.ssid) == .orderedAscending
            case .bssid: return lhs.bssid.localizedStandardCompare(rhs.bssid) == .orderedAscending
            case .band: return lhs.band.localizedStandardCompare(rhs.band) == .orderedAscending
            case .channel: return lhs.channel < rhs.channel
            case .clients: return lhs.clients < rhs.clients
            case .utilization:
                return (lhs.utilization ?? .min) < (rhs.utilization ?? .min)
            case .signal: return lhs.signal < rhs.signal
            }
        }
        return apAscending ? ordered : ordered.reversed()
    }

    private func sortedObservations(_ rows: [ClientObservation]) -> [ClientObservation] {
        let ordered = rows.sorted { lhs, rhs in
            switch clientSortKey {
            case .mac: return lhs.mac.localizedStandardCompare(rhs.mac) == .orderedAscending
            case .vendor:
                return lhs.vendor.localizedStandardCompare(rhs.vendor) == .orderedAscending
            case .bssid: return lhs.bssid.localizedStandardCompare(rhs.bssid) == .orderedAscending
            case .frames: return lhs.frames < rhs.frames
            case .rssi: return (lhs.rssi ?? .min) < (rhs.rssi ?? .min)
            case .probes:
                return lhs.probes.joined(separator: ", ")
                    .localizedStandardCompare(rhs.probes.joined(separator: ", "))
                    == .orderedAscending
            }
        }
        return clientAscending ? ordered : ordered.reversed()
    }

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
                    Button {
                        capture()
                    } label: {
                        Label(
                            isCapturing ? "Capturing…" : "Capture 10 s of client frames",
                            systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing || interfaces.isEmpty)
                    if isCapturing { ProgressView().controlSize(.small) }
                    Spacer()
                    if !observations.isEmpty {
                        Button("Clear capture") { observations = [] }
                            .buttonStyle(.borderless)
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
                TableSortControl(
                    options: APSortKey.allCases.map { ($0, $0.title) },
                    selection: $apSortKey, ascending: $apAscending)
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
                Table(sortedAccessPoints(snapshot.busiestAccessPoints)) {
                    TableColumn("SSID", value: \.ssid)
                    TableColumn("BSSID", value: \.bssid)
                        .width(AppColumnWidth.wide)
                    TableColumn("Band", value: \.band)
                        .width(AppColumnWidth.compact)
                    TableColumn("Ch") { Text("\($0.channel)").monospacedDigit() }
                        .width(AppColumnWidth.short)
                    TableColumn("Clients") { row in
                        HStack(spacing: DesignToken.Spacing.tight) {
                            Text("\(row.clients)").monospacedDigit().bold()
                            ProgressView(
                                value: Double(min(row.clients, 30)), total: 30
                            )
                            .progressViewStyle(.linear)
                            .frame(width: 46)
                        }
                    }
                    .width(AppColumnWidth.medium)
                    TableColumn("Util") { row in
                        Text(row.utilization.map { "\($0)%" } ?? "—")
                            .monospacedDigit()
                            .foregroundColor(
                                (row.utilization ?? 0) >= 60
                                    ? AppPalette.warning : .secondary)
                    }
                    .width(AppColumnWidth.short)
                    TableColumn("RSSI") { Text("\($0.signal) dBm").monospacedDigit() }
                        .width(AppColumnWidth.compact)
                }
                .frame(height: ToolkitTableHeight.rows(snapshot.busiestAccessPoints.count))
                .appTableSurface()
            }
        }
    }

    private var clientTable: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack {
                SectionLabel(text: "Captured clients")
                TableSortControl(
                    options: ClientSortKey.allCases.map { ($0, $0.title) },
                    selection: $clientSortKey, ascending: $clientAscending)
                Spacer()
            }
            Table(sortedObservations(observations), selection: $selection) {
                TableColumn("MAC", value: \.mac)
                TableColumn("Vendor", value: \.vendor)
                    .width(AppColumnWidth.wide)
                TableColumn("BSSID", value: \.bssid)
                    .width(AppColumnWidth.wide)
                TableColumn("Frames") { Text("\($0.frames)").monospacedDigit() }
                    .width(AppColumnWidth.short)
                TableColumn("RSSI") { Text($0.rssi.map { "\($0) dBm" } ?? "—") }
                    .width(AppColumnWidth.short)
                TableColumn("Probes") { row in
                    Text(row.probes.isEmpty ? "—" : row.probes.joined(separator: ", "))
                        .lineLimit(1)
                        .help(row.probes.joined(separator: "\n"))
                }
            }
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
