import AppKit
import LanFiCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @ObservedObject var uptime: UptimeMonitor
    @ObservedObject var meter: MenuBarMeterModel
    @ObservedObject var connectivity: ConnectivityWatchdog
    @ObservedObject var route: RouteMonitor
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var toolkit: ToolkitViewModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppSettingsKey.menuBarUnit.rawValue) private var unitRaw = "bits"

    private var unit: ThroughputFormatter.Unit {
        unitRaw == "bytes" ? .bytes : .bits
    }

    private var statusColor: Color {
        switch diagnostics.overall {
        case .pass: return AppPalette.ok
        case .warning: return AppPalette.warning
        case .fail: return AppPalette.danger
        default: return AppPalette.muted
        }
    }

    private var connected: NetworkModel? {
        guard let bssid = viewModel.currentConnectedBSSID else { return nil }
        return viewModel.networks.first { $0.bssid == bssid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            alerts

            HStack(alignment: .firstTextBaseline) {
                Text("LanFi").font(.headline)
                Spacer()
                Text("\(viewModel.networks.count) networks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            throughputCard
            linkCard
            connectivityCard
            routeCard
            latencyCard
            publicIPRow

            if !uptime.targets.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(uptime.downCount > 0 ? AppPalette.danger : AppPalette.ok)
                        .frame(width: 7, height: 7)
                    Text(
                        uptime.downCount > 0
                            ? "\(uptime.downCount) uptime target\(uptime.downCount == 1 ? "" : "s") down"
                            : "Uptime: all \(uptime.targets.count) up"
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    Spacer()
                    Button("Open") {
                        showTool(.uptimeMonitor)
                    }
                    .controlSize(.mini)
                }
            }

            if let best = viewModel.analysis.bestChannel(for: .band5) {
                Text("Recommended 5 GHz: channel \(best.channel) · \(best.widthMHz) MHz")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")

            Button {
                // D2: the menu-bar "Open" target is the all-band RF overview.
                // Setting the shared state (instead of posting notifications)
                // works even when the window is not open yet.
                toolkit.select(.wifiAnalyzer)
                uiState.selectedBottomTab = 9
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open LanFi", systemImage: "macwindow")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit LanFi", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .padding(DesignToken.Spacing.medium)
        .frame(width: 320)
        .onAppear {
            meter.start()
            connectivity.start()
        }
    }

    // MARK: - Blocks

    @ViewBuilder
    private var alerts: some View {
        if !viewModel.menuBarAlerts.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(viewModel.menuBarAlerts.prefix(3)) { alert in
                    HStack(alignment: .top, spacing: 6) {
                        Image(
                            systemName: alert.severity == .critical
                                ? "exclamationmark.triangle.fill"
                                : alert.severity == .warning
                                    ? "exclamationmark.circle.fill" : "info.circle.fill"
                        )
                        .foregroundColor(
                            alert.severity == .critical
                                ? AppPalette.danger
                                : alert.severity == .warning ? AppPalette.warning : AppPalette.info)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(alert.title).font(.caption.bold())
                            Text(alert.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(DesignToken.Spacing.small)
            .background(
                DesignToken.Surface.warningFill,
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
        }
    }

    private var throughputCard: some View {
        AppCard(padding: DesignToken.Spacing.small) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel(text: "Throughput")
                    Spacer()
                    if let primary = meter.primaryRate {
                        Text(primary.interfaceName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                MenuBarSparkline(values: meter.samples, tint: AppPalette.info)
                    .frame(height: 28)
                HStack(spacing: DesignToken.Spacing.medium) {
                    StatTile(
                        value: ThroughputFormatter.rate(
                            meter.primaryRate?.receivedBytesPerSecond ?? 0, unit: unit),
                        label: "Download", tint: AppPalette.ok)
                    StatTile(
                        value: ThroughputFormatter.rate(
                            meter.primaryRate?.sentBytesPerSecond ?? 0, unit: unit),
                        label: "Upload", tint: AppPalette.info)
                }
            }
        }
    }

    @ViewBuilder
    private var linkCard: some View {
        if let connected {
            AppCard(padding: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    Image(systemName: "wifi")
                        .foregroundColor(AppPalette.band(connected.band))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connected.displaySSID)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text(
                            "\(connected.bandLabel) · Ch \(connected.channel) · \(connected.channelWidthMHz) MHz · \(connected.maxRateLabel) Mbit/s"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        Text("\(connected.signal) dBm · SNR \(connected.snrLabel)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(viewModel.metrics(for: connected)?.qualityScore ?? 0)")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(
                                AppPalette.quality(
                                    viewModel.metrics(for: connected)?.qualityScore ?? 0))
                        SectionLabel(text: "Quality")
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash").foregroundColor(.secondary)
                Text("Not connected to a Wi-Fi network")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var latencyCard: some View {
        AppCard(padding: DesignToken.Spacing.small) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    SectionLabel(text: "Diagnostics")
                    Spacer()
                    Text(diagnostics.overall.label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("Run") {
                        Task { await diagnostics.run() }
                    }
                    .controlSize(.mini)
                    .disabled(diagnostics.isRunning)
                }
                if diagnostics.latencyChecks.isEmpty {
                    Text("Run diagnostics to measure gateway and public latency.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(diagnostics.latencyChecks.prefix(3)) { check in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color(for: check.status))
                                .frame(width: 5, height: 5)
                            Text(check.title)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(check.value)
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private var connectivityCard: some View {
        AppCard(padding: DesignToken.Spacing.small) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectivityColor)
                        .frame(width: 7, height: 7)
                    SectionLabel(text: "Connectivity")
                    Spacer()
                    if connectivity.isChecking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(connectivity.verdict.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button("Check") {
                        Task { await connectivity.checkNow() }
                    }
                    .controlSize(.mini)
                    .disabled(connectivity.isChecking || !connectivity.isEnabled)
                }
                if !connectivity.isEnabled {
                    Text("Connectivity checks are off. Turn them on in Settings → General.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if let latency = connectivity.latencyMilliseconds,
                    connectivity.verdict.isOnline
                {
                    Text("\(latency) ms · checked \(checkedAtText)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                } else if let checkedAtText {
                    Text("Last checked \(checkedAtText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var routeCard: some View {
        AppCard(padding: DesignToken.Spacing.small) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(route.isRunning ? AppPalette.ok : AppPalette.muted)
                        .frame(width: 7, height: 7)
                    SectionLabel(text: "Route")
                    Spacer()
                    if route.isRunning {
                        Text(route.target)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Button("Stop") { route.stop() }
                            .controlSize(.mini)
                    } else {
                        Text("Not monitoring")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Button("Start") {
                            route.start(
                                host: route.target.isEmpty
                                    ? AnalysisTarget.shared.value : route.target)
                        }
                        .controlSize(.mini)
                    }
                }
                if route.isRunning {
                    MenuBarSparkline(
                        values: route.samples.compactMap(\.destinationLatencyMilliseconds),
                        tint: AppPalette.ok
                    )
                    .frame(height: 24)
                    HStack(spacing: DesignToken.Spacing.medium) {
                        StatTile(
                            value: ToolkitFormat.milliseconds(
                                route.samples.last?.destinationLatencyMilliseconds),
                            label: String(localized: "Latest latency"), tint: AppPalette.info)
                        StatTile(
                            value: "\(route.samples.count)",
                            label: String(localized: "Samples"),
                            tint: AppPalette.muted)
                    }
                } else {
                    Text("Open the Route Monitor tool to choose a destination.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var checkedAtText: String? {
        connectivity.lastCheckedAt.map {
            $0.formatted(date: .omitted, time: .standard)
        }
    }

    private var connectivityColor: Color {
        switch connectivity.verdict {
        case .online: return AppPalette.ok
        case .captivePortal: return AppPalette.warning
        case .offline: return AppPalette.danger
        case .unknown: return AppPalette.muted
        }
    }

    private var publicIPRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                if let ip = meter.publicIP {
                    Text(ip)
                        .font(.caption.monospaced())
                    if let country = meter.publicCountry, !country.isEmpty {
                        Text(country)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if meter.isLookingUpPublicIP {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("Public IP not checked")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(meter.publicIP == nil ? "Look up" : "Refresh") {
                    meter.refreshPublicIP()
                }
                .controlSize(.mini)
                .disabled(meter.isLookingUpPublicIP)
            }
            if let error = meter.publicIPError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(AppPalette.danger)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Helpers

    private func color(for status: DiagnosticStatus) -> Color {
        switch status {
        case .pass: return AppPalette.ok
        case .warning: return AppPalette.warning
        case .fail: return AppPalette.danger
        default: return AppPalette.muted
        }
    }

    private func showTool(_ tool: ToolboxTool) {
        NotificationCenter.default.post(
            name: .lanfiShowToolkit, object: nil,
            userInfo: ["tool": tool.rawValue])
        openWindow(id: "main")
    }
}
