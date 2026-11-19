import SwiftUI

/// The default screen: a summary of everything LanFi already watches, with one
/// route into the tool that explains each number.
///
/// The Wi-Fi analyzer is one card here, not the whole app. The dashboard reads
/// the same shared services the menu bar and the toolkit use, so it never
/// starts a second poller or a second scan loop.
struct OverviewDashboardView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var uptime: UptimeMonitor
    @EnvironmentObject private var meter: MenuBarMeterModel
    @StateObject private var connectivity = ConnectivityWatchdog.shared
    @StateObject private var accounting = TrafficAccounting.shared
    @StateObject private var gateway = GatewayGuard.shared
    @StateObject private var vpn = VPNGuard.shared
    @StateObject private var automation = LinkAutomation.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.card) {
                HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
                    connectionCard
                    internetCard
                }
                keyMetrics
                HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
                    bandCard
                    channelCard
                }
                HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
                    throughputCard
                    uptimeCard
                }
                HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
                    quickActions
                    linkCard
                }
                footer
            }
            .appContentPadding()
        }
    }

    // MARK: - Connection and internet

    private var connected: NetworkModel? { analyzer.connectedNetwork }

    private var qualityScore: Int? {
        guard let connected else { return nil }
        return analyzer.metrics(for: connected)?.qualityScore
    }

    private var connectionCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Connection")
                    Spacer()
                    if let network = connected {
                        ToolkitStatusPill(
                            text: network.band.label, tone: .neutral)
                    }
                }
                if let network = connected {
                    HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
                        Text(analyzer.displayName(for: network))
                            .font(.title3.bold())
                            .lineLimit(1)
                        Spacer(minLength: DesignToken.Spacing.small)
                        Text("\(network.signal) dBm")
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    Text(
                        verbatim:
                            "Ch \(network.channel) · \(network.channelWidthLabel) · \(network.security)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                    LevelBar(
                        fraction: levelFraction(for: network),
                        color: AppPalette.band(network.band))
                    HStack {
                        Text("Quality")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let qualityScore {
                            Text(verbatim: "\(qualityScore)/100")
                                .font(.caption2.monospacedDigit())
                        }
                        Spacer()
                        Text(verbatim: rateLine(for: network))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No Wi-Fi connection")
                        .font(.callout)
                    Text(
                        "Ethernet may be carrying traffic, or Location access is off so SSIDs are hidden."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    AppButton("Open Wi-Fi Analyzer", tone: .secondary) {
                        toolkit.select(.wifiAnalyzer)
                    }
                }
            }
        }
    }

    private var internetCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Internet")
                    Spacer()
                    ToolkitStatusPill(
                        text: connectivity.verdict.title,
                        tone: connectivityTone)
                }
                Text(latencyLine)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(checkedLine(connectivity.lastCheckedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                HStack(spacing: DesignToken.Spacing.small) {
                    AppButton(
                        "Check now", systemImage: "arrow.clockwise",
                        isBusy: connectivity.isChecking,
                        isEnabled: !connectivity.isChecking
                    ) {
                        Task { await connectivity.checkNow() }
                    }
                    AppButton("Open Internet Check", tone: .quiet) {
                        toolkit.select(.internetCheck)
                    }
                }
            }
        }
    }

    private var connectivityTone: ToolkitTone {
        switch connectivity.verdict {
        case .online: return .good
        case .captivePortal: return .warning
        case .offline: return .bad
        case .unknown: return .neutral
        }
    }

    private var latencyLine: String {
        guard let latency = connectivity.latencyMilliseconds else { return "—" }
        return "\(latency) ms"
    }

    // MARK: - Key metrics

    private var keyMetrics: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
            metricTile(
                title: "Gateway", value: gateway.gatewayIP ?? "—",
                detail: resolverLine, icon: "point.topleft.down.curvedto.point.bottomright.up",
                tone: gateway.macChangeCount > 0 ? .warning : .neutral)
            metricTile(
                title: "VPN", value: vpnValue, detail: leakLine, icon: "lock.shield",
                tone: vpn.report.hasLeak ? .bad : (vpn.report.vpn.isUp ? .good : .neutral))
            metricTile(
                title: "Traffic today",
                value: TrafficByteFormat.string(accounting.volume(.today).total),
                detail: rateText, icon: "arrow.up.arrow.down", tone: .neutral)
            metricTile(
                title: "Wi-Fi", value: "\(analyzer.networks.count) networks",
                detail: scanLine, icon: "wifi",
                tone: connected == nil ? .warning : .good)
        }
    }

    private func metricTile(
        title: LocalizedStringKey, value: String, detail: String, icon: String, tone: ToolkitTone
    ) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.tight) {
                HStack(spacing: DesignToken.Spacing.tight) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tone.color)
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                }
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var resolverLine: String {
        switch gateway.resolverCheck.verdict {
        case .match: return String(localized: "DNS matches the public resolver")
        case .mismatch: return String(localized: "DNS answers differ")
        case .unknown: return String(localized: "DNS not checked yet")
        }
    }

    private var vpnValue: String {
        guard vpn.report.vpn.isUp else { return String(localized: "Off") }
        return vpn.report.vpn.interfaceLabel ?? String(localized: "On")
    }

    private var leakLine: String {
        if vpn.report.hasLeak { return String(localized: "Leak reported") }
        guard vpn.report.vpn.isUp else { return String(localized: "No tunnel in use") }
        return String(localized: "No leaks")
    }

    private var rateText: String {
        guard let rate = meter.primaryRate else { return String(localized: "Not sampled yet") }
        return "\(TrafficByteFormat.string(UInt64(rate.receivedBytesPerSecond)))/s"
    }

    private var scanLine: String {
        guard let last = analyzer.lastScanDate else { return String(localized: "No scan yet") }
        return String(localized: "Last scan") + " "
            + last.formatted(date: .omitted, time: .shortened)
    }

    // MARK: - Wi-Fi landscape

    private var bandCounts: [(band: WiFiBand, count: Int)] {
        WiFiBand.allCases.compactMap { band in
            let count = analyzer.networks.filter { $0.band == band }.count
            return count > 0 ? (band, count) : nil
        }
    }

    private var bandCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Networks by band")
                if bandCounts.isEmpty {
                    Text("No scan yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            ForEach(bandCounts, id: \.band) { entry in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(AppPalette.band(entry.band))
                                    .frame(
                                        width: max(
                                            4,
                                            geometry.size.width * CGFloat(entry.count)
                                                / CGFloat(max(totalNetworks, 1))))
                            }
                        }
                    }
                    .frame(height: 10)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(bandCounts, id: \.band) { entry in
                            HStack(spacing: DesignToken.Spacing.tight) {
                                Circle()
                                    .fill(AppPalette.band(entry.band))
                                    .frame(width: 7, height: 7)
                                Text(entry.band.label)
                                    .font(.caption2)
                                Spacer()
                                Text(verbatim: "\(entry.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var totalNetworks: Int {
        bandCounts.reduce(0) { $0 + $1.count }
    }

    /// Six busiest channels, so an over-crowded 2.4 GHz channel is visible
    /// before opening the analyzer.
    private var topChannels: [(channel: Int, count: Int)] {
        var counts: [Int: Int] = [:]
        for network in analyzer.networks {
            counts[network.channel, default: 0] += 1
        }
        let ordered = counts.map { (channel: $0.key, count: $0.value) }.sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.channel < rhs.channel }
            return lhs.count > rhs.count
        }
        return Array(ordered.prefix(6))
    }

    private var channelCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Busiest channels")
                if topChannels.isEmpty {
                    Text("No scan yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    let peak = max(topChannels.map(\.count).max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: DesignToken.Spacing.small) {
                        ForEach(topChannels, id: \.channel) { entry in
                            VStack(spacing: 3) {
                                Text(verbatim: "\(entry.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(0.75))
                                    .frame(height: max(4, 44 * CGFloat(entry.count) / CGFloat(peak)))
                                Text(verbatim: "\(entry.channel)")
                                    .font(.caption2.monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 76, alignment: .bottom)
                    AppButton("Open Wi-Fi Analyzer", tone: .quiet) {
                        toolkit.select(.wifiAnalyzer)
                    }
                }
            }
        }
    }

    // MARK: - Throughput and uptime

    private var throughputCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Live throughput")
                if meter.samples.count < 2 {
                    Text("Not sampled yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    DashboardSparkline(samples: meter.samples)
                        .frame(height: 46)
                }
                HStack(spacing: DesignToken.Spacing.card) {
                    rateColumn(
                        title: "Down", icon: "arrow.down",
                        value: meter.primaryRate?.receivedBytesPerSecond)
                    rateColumn(
                        title: "Up", icon: "arrow.up",
                        value: meter.primaryRate?.sentBytesPerSecond)
                    Spacer()
                }
            }
        }
    }

    private func rateColumn(title: LocalizedStringKey, icon: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            Text(
                value.map { "\(TrafficByteFormat.string(UInt64($0)))/s" } ?? "—"
            )
            .font(.caption.monospacedDigit())
        }
    }

    private var uptimeCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Uptime")
                if uptime.targets.isEmpty {
                    Text("No targets yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(uptime.targets.prefix(3)) { target in
                        let state = uptime.state(for: target)
                        HStack(spacing: DesignToken.Spacing.small) {
                            Circle()
                                .fill(uptimeTone(state).color)
                                .frame(width: 7, height: 7)
                            Text(target.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(uptimeDetail(state))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                AppButton("Open Uptime Monitor", tone: .quiet) {
                    toolkit.select(.uptimeMonitor)
                }
            }
        }
    }

    private func uptimeTone(_ state: UptimeTargetState) -> ToolkitTone {
        switch state.isUp {
        case true?: return .good
        case false?: return .bad
        case nil: return .neutral
        }
    }

    private func uptimeDetail(_ state: UptimeTargetState) -> String {
        if let percent = state.uptimePercent {
            return String(format: "%.1f %%", percent)
        }
        if let latency = state.averageLatencyMilliseconds {
            return String(format: "%.0f ms", latency)
        }
        return String(localized: "No checks yet")
    }

    // MARK: - Actions

    private var quickActions: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Quick actions")
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DesignToken.Spacing.small),
                        GridItem(.flexible(), spacing: DesignToken.Spacing.small),
                    ],
                    spacing: DesignToken.Spacing.small
                ) {
                    AppButton("Wi-Fi Analyzer", systemImage: "wifi") {
                        toolkit.select(.wifiAnalyzer)
                    }
                    AppButton("Ping", systemImage: "dot.radiowaves.left.and.right") {
                        toolkit.select(.ping)
                    }
                    AppButton("DNS Lookup", systemImage: "magnifyingglass") {
                        toolkit.select(.dnsLookup)
                    }
                    AppButton("Speed Test", systemImage: "speedometer") {
                        toolkit.select(.speedTest)
                    }
                    AppButton("Connections", systemImage: "arrow.triangle.branch") {
                        toolkit.select(.openConnections)
                    }
                    AppButton("LAN Scanner", systemImage: "desktopcomputer") {
                        toolkit.select(.lanScanner)
                    }
                }
            }
        }
    }

    private var linkCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Link automation")
                HStack(spacing: DesignToken.Spacing.tight) {
                    Text(automation.isEnabled ? String(localized: "On") : String(localized: "Off"))
                        .font(.caption.weight(.semibold))
                    if automation.isPaused && automation.isEnabled {
                        Text("Paused")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if automation.wiredConnected {
                        Text(automation.wiredInterface ?? "")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                Text(wifiAutomationLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var wifiAutomationLine: String {
        guard automation.isEnabled else {
            return String(localized: "Off. Enable it in Settings → General to turn Wi-Fi off while a cable is up.")
        }
        switch automation.wifiPowerOn {
        case true?: return String(localized: "Wi-Fi is on")
        case false?: return String(localized: "Wi-Fi is off, Ethernet carries traffic")
        case nil: return String(localized: "Wi-Fi state unknown")
        }
    }

    private var footer: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption2)
            Text(scanLine)
                .font(.caption2)
            Spacer()
            Text(
                "Every number here is measured on this Mac. Nothing is uploaded."
            )
            .font(.caption2)
        }
        .foregroundColor(.secondary)
    }

    // MARK: - Helpers

    /// -100…-30 dBm mapped to 0…1 for the compact bar.
    private func levelFraction(for network: NetworkModel) -> Double {
        let clamped = min(max(Double(network.signal), -100), -30)
        return (clamped + 100) / 70
    }

    private func rateLine(for network: NetworkModel) -> String {
        guard let rate = network.maxRate, rate > 0 else { return "" }
        return String(format: "%.0f Mbps", rate)
    }

    private func checkedLine(_ date: Date?) -> String {
        guard let date else { return String(localized: "Not checked yet") }
        return String(localized: "Checked at") + " "
            + date.formatted(date: .omitted, time: .shortened)
    }
}

/// A proportion-filled capsule for signal strength.
private struct LevelBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(6, geometry.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A minimal line chart for the meter's rolling samples; no axes, no labels,
/// because the card already prints the numbers.
private struct DashboardSparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geometry in
            let peak = max(samples.max() ?? 1, 1)
            Path { path in
                for (index, sample) in samples.enumerated() {
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                    let y = geometry.size.height * (1 - CGFloat(sample / peak))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
