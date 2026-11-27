import SwiftUI

/// The default screen: what this Mac is connected to, whether it works, and
/// what LanFi is watching right now, with one route into the tool that explains
/// each number.
///
/// The Wi-Fi analyzer is one part of the app, not the whole of it. Every value
/// comes from a service the app already runs — the dashboard never starts a scan
/// loop or a second sampler of its own.
struct OverviewDashboardView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    /// Defaults to the one shared meter so the screen also builds outside the
    /// main window (previews, snapshots, smoke tests) without an environment.
    @ObservedObject var meter: MenuBarMeterModel = .shared
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var uptime: UptimeMonitor
    @StateObject private var connectivity = ConnectivityWatchdog.shared
    @StateObject private var accounting = TrafficAccounting.shared
    @StateObject private var gateway = GatewayGuard.shared
    @StateObject private var vpn = VPNGuard.shared
    @StateObject private var automation = LinkAutomation.shared
    @StateObject private var locationAccess = LocationAccessCenter.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.card) {
                attentionCard
                heroRow
                keyMetrics
                liveRow
                wifiRow
                actionRow
                footer
            }
            .appContentPadding()
        }
    }

    // MARK: - Plain-language summary

    /// What an ordinary user should look at first. Every item is a check the
    /// app already runs; the card only ranks them and links to the tool that
    /// explains the number, instead of leaving the reader to read five tiles.
    private enum Destination {
        case tool(ToolboxTool)
        case settings
    }

    private struct Issue: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let tone: ToolkitTone
        let destination: Destination
    }

    private var issues: [Issue] {
        var found: [Issue] = []
        switch connectivity.verdict {
        case .offline:
            found.append(
                Issue(
                    id: "offline", title: String(localized: "No internet"),
                    detail: String(localized: "The router answers but nothing beyond it does."),
                    icon: "wifi.exclamationmark", tone: .bad,
                    destination: .tool(.internetCheck)))
        case .captivePortal:
            found.append(
                Issue(
                    id: "portal", title: String(localized: "Sign-in page waiting"),
                    detail: String(localized: "This network asks you to sign in before it works."),
                    icon: "hand.raised", tone: .warning, destination: .tool(.internetCheck)))
        case .online, .unknown:
            break
        }
        if vpn.report.hasLeak {
            found.append(
                Issue(
                    id: "vpn-leak", title: String(localized: "VPN leak"),
                    detail: String(localized: "Traffic escapes the tunnel while the VPN is up."),
                    icon: "exclamationmark.shield", tone: .bad,
                    destination: .tool(.securityWatch)))
        }
        if case .mismatch = gateway.resolverCheck.verdict {
            found.append(
                Issue(
                    id: "dns", title: String(localized: "DNS answers differ"),
                    detail: String(localized: "A public resolver disagrees with this network's DNS."),
                    icon: "questionmark.circle", tone: .warning,
                    destination: .tool(.internetCheck)))
        }
        if let network = connected, network.signal < -75 {
            found.append(
                Issue(
                    id: "signal", title: String(localized: "Weak Wi-Fi signal"),
                    detail: String(localized: "Move closer to the access point for a stable link."),
                    icon: "cellularbars", tone: .warning,
                    destination: .tool(.wifiAnalyzer)))
        }
        if let network = connected, isInsecure(network) {
            found.append(
                Issue(
                    id: "security", title: String(localized: "This network is not protected"),
                    detail: String(localized: "Traffic is not encrypted over the air on this network."),
                    icon: "lock.open", tone: .warning,
                    destination: .tool(.wifiAnalyzer)))
        }
        if !locationAccess.isAuthorized {
            found.append(
                Issue(
                    id: "location", title: String(localized: "Network names are hidden"),
                    detail: String(
                        localized:
                            "macOS needs Location access before LanFi can show SSIDs and channels."),
                    icon: "location.slash", tone: .warning, destination: .settings))
        }
        return found
    }

    private func isInsecure(_ network: NetworkModel) -> Bool {
        let security = network.security.lowercased()
        return security.contains("open") || security.contains("none")
            || security.contains("wep")
    }

    @ViewBuilder
    private var attentionCard: some View {
        let issues = self.issues
        if issues.isEmpty {
            if connectivity.verdict == .online {
                HStack(spacing: DesignToken.Spacing.tight) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(AppPalette.ok)
                    Text("Everything looks fine: online, stable signal and no leaks.")
                        .font(.caption)
                    Spacer()
                }
                .padding(.vertical, DesignToken.Spacing.tight)
                .padding(.horizontal, DesignToken.Spacing.small)
            }
        } else {
            ToolkitCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    HStack {
                        ToolkitSectionLabel(text: "Worth a look")
                        Spacer()
                        Text(verbatim: "\(issues.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    ForEach(issues.prefix(3)) { issue in
                        HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
                            Image(systemName: issue.icon)
                                .foregroundColor(issue.tone.color)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.title)
                                    .font(.callout.weight(.medium))
                                Text(issue.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: DesignToken.Spacing.small)
                            AppButton("Open", tone: .quiet) { open(issue.destination) }
                        }
                    }
                }
            }
        }
    }

    private func open(_ destination: Destination) {
        switch destination {
        case .tool(let tool): toolkit.select(tool)
        case .settings: SettingsRouter.shared.open(.general)
        }
    }

    private func signalWord(_ rssi: Int) -> String {
        switch rssi {
        case (-55)...: return String(localized: "Excellent signal")
        case (-67)..<(-55): return String(localized: "Good signal")
        case (-75)..<(-67): return String(localized: "Fair signal")
        default: return String(localized: "Weak signal")
        }
    }

    private func signalTone(_ rssi: Int) -> ToolkitTone {
        switch rssi {
        case (-67)...: return .good
        case (-75)..<(-67): return .warning
        default: return .bad
        }
    }

    // MARK: - Hero: link and internet

    private var connected: NetworkModel? { analyzer.connectedNetwork }

    private var qualityScore: Int? {
        guard let connected else { return nil }
        return analyzer.metrics(for: connected)?.qualityScore
    }

    private var heroRow: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
            connectionCard.dashboardLink { toolkit.select(.wifiAnalyzer) }
            internetCard.dashboardLink { toolkit.select(.internetCheck) }
        }
    }

    private var connectionCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Connection")
                    Spacer()
                    if let network = connected {
                        ToolkitStatusPill(text: network.band.label, tone: .neutral)
                    }
                }

                if let network = connected {
                    Text(analyzer.displayName(for: network))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: DesignToken.Spacing.compact) {
                        signalChip(network)
                        if let qualityScore {
                            chip(
                                title: String(localized: "Quality"),
                                value: "\(qualityScore)/100",
                                tone: qualityScore >= 70 ? .good : (qualityScore >= 45 ? .warning : .bad)
                            )
                        }
                        if network.maxRate.map({ $0 > 0 }) == true {
                            chip(
                                title: String(localized: "Link"),
                                value: String(format: "%.0f Mbps", network.maxRate ?? 0),
                                tone: .neutral
                            )
                        }
                        Spacer(minLength: 0)
                    }

                    LevelBar(
                        fraction: levelFraction(for: network),
                        color: AppPalette.band(network.band))

                    Text(
                        verbatim:
                            "Ch \(network.channel) · \(network.channelWidthLabel) · \(network.security)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                } else {
                    Text("No Wi-Fi connection")
                        .font(.headline)
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

                // Gateway, its MAC and the DNS verdict describe the active link,
                // not Wi-Fi: keep them on screen when Ethernet carries traffic.
                Divider()

                HStack(spacing: DesignToken.Spacing.card) {
                    fact(
                        title: "Gateway", value: gateway.gatewayIP ?? "—",
                        detail: gateway.gatewayMAC)
                    fact(
                        title: "DNS", value: dnsShortValue,
                        detail: resolverLine, tone: dnsTone)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private var internetCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Internet")
                    Spacer()
                    ToolkitStatusPill(text: connectivity.verdict.title, tone: connectivityTone)
                }

                HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.tight) {
                    Text(latencyLine)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Text(checkedLine(connectivity.lastCheckedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let ip = meter.publicIP {
                    Divider()
                    fact(
                        title: "Public IP", value: ip,
                        detail: meter.publicCountry)
                }

                HStack(spacing: DesignToken.Spacing.small) {
                    AppButton(
                        "Check now", systemImage: "arrow.clockwise",
                        isBusy: connectivity.isChecking,
                        isEnabled: !connectivity.isChecking
                    ) {
                        Task { await connectivity.checkNow() }
                    }
                    .frame(maxWidth: .infinity)
                    AppButton("Internet Check", tone: .secondary) {
                        toolkit.select(.internetCheck)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
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
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: DesignToken.Spacing.card),
                count: 4),
            spacing: DesignToken.Spacing.card
        ) {
            metricTile(
                title: "VPN", value: vpnValue, detail: leakLine, icon: "lock.shield",
                tone: vpn.report.hasLeak ? .bad : (vpn.report.vpn.isUp ? .good : .neutral)
            ) { toolkit.select(.securityWatch) }
            metricTile(
                title: "Wi-Fi", value: "\(analyzer.networks.count) networks",
                detail: scanLine, icon: "wifi",
                tone: connected == nil ? .warning : .good
            ) { toolkit.select(.wifiAnalyzer) }
            metricTile(
                title: "Traffic today",
                value: TrafficByteFormat.string(accounting.volume(.today).total),
                detail: rateText, icon: "arrow.up.arrow.down", tone: .neutral
            ) { toolkit.select(.processTraffic) }
            metricTile(
                title: "Signal",
                value: connected.map { "\($0.signal) dBm" } ?? "—",
                detail: connected.map { signalWord($0.signal) }
                    ?? String(localized: "No Wi-Fi connection"),
                icon: "cellularbars",
                tone: connected.map { signalTone($0.signal) } ?? .neutral
            ) { toolkit.select(.wifiAnalyzer) }
        }
    }

    private func metricTile(
        title: LocalizedStringKey, value: String, detail: String, icon: String, tone: ToolkitTone,
        action: @escaping () -> Void
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
                    Spacer(minLength: 0)
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
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .dashboardLink(action)
    }

    private var automationTone: ToolkitTone {
        guard automation.isEnabled else { return .neutral }
        return automation.isPaused ? .warning : .good
    }

    private var dnsShortValue: String {
        switch gateway.resolverCheck.verdict {
        case .match: return String(localized: "Match")
        case .mismatch: return String(localized: "Mismatch")
        case .unknown: return "—"
        }
    }

    private var dnsTone: ToolkitTone {
        switch gateway.resolverCheck.verdict {
        case .match: return .good
        case .mismatch: return .bad
        case .unknown: return .neutral
        }
    }

    private var resolverLine: String {
        switch gateway.resolverCheck.verdict {
        case .match: return String(localized: "Public resolver agrees")
        case .mismatch: return String(localized: "Answers differ")
        case .unknown: return String(localized: "Not checked yet")
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

    // MARK: - Live throughput and uptime

    private var liveRow: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
            throughputCard.dashboardLink { toolkit.select(.speedTest) }
            uptimeCard.dashboardLink { toolkit.select(.uptimeMonitor) }
        }
    }

    private var throughputCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Live throughput")
                    Spacer()
                    if let rate = meter.primaryRate {
                        Text(verbatim: "\(TrafficByteFormat.string(UInt64(rate.totalBytesPerSecond)))/s")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
                if meter.samples.count < 2 {
                    Text("Not sampled yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
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
                    AppButton("Speed Test", tone: .quiet) {
                        toolkit.select(.speedTest)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
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
                HStack {
                    ToolkitSectionLabel(text: "Uptime")
                    Spacer()
                    AppButton("Open", tone: .quiet) {
                        toolkit.select(.uptimeMonitor)
                    }
                }
                if uptime.targets.isEmpty {
                    Text("No targets yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
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
                HStack {
                    ToolkitSectionLabel(text: "Busiest channels")
                    Spacer()
                    AppButton("Analyzer", tone: .quiet) {
                        toolkit.select(.wifiAnalyzer)
                    }
                }
                if topChannels.isEmpty {
                    Text("No scan yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .center)
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }

    private var wifiRow: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
            bandCard.dashboardLink { toolkit.select(.wifiAnalyzer) }
            channelCard.dashboardLink { toolkit.select(.wifiAnalyzer) }
        }
    }

    // MARK: - Actions

    private var quickTools: [(title: LocalizedStringKey, icon: String, tool: ToolboxTool)] {
        [
            ("Wi-Fi Analyzer", "wifi", .wifiAnalyzer),
            ("Ping", "dot.radiowaves.left.and.right", .ping),
            ("DNS Lookup", "magnifyingglass", .dnsLookup),
            ("Speed Test", "speedometer", .speedTest),
            ("Connections", "arrow.triangle.branch", .openConnections),
            ("LAN Scanner", "desktopcomputer", .lanScanner),
        ]
    }

    private var actionRow: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.card) {
            ToolkitCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Quick actions")
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: DesignToken.Spacing.small),
                            count: 3),
                        spacing: DesignToken.Spacing.small
                    ) {
                        ForEach(quickTools.indices, id: \.self) { index in
                            AppButton(
                                quickTools[index].title,
                                systemImage: quickTools[index].icon
                            ) {
                                toolkit.select(quickTools[index].tool)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .dashboardLink { toolkit.select(.advancedTools) }

            linkCard
                .frame(maxWidth: .infinity)
                .dashboardLink { SettingsRouter.shared.open(.general) }
        }
    }

    private var linkCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    ToolkitSectionLabel(text: "Link automation")
                    Spacer()
                    ToolkitStatusPill(
                        text: automation.isEnabled
                            ? (automation.isPaused
                                ? String(localized: "Paused") : String(localized: "On"))
                            : String(localized: "Off"),
                        tone: automationTone)
                }
                if automation.wiredConnected {
                    Text(verbatim: automation.wiredInterface ?? "")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Text(wifiAutomationLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - Small pieces

    private func chip(title: String, value: String, tone: ToolkitTone) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(verbatim: value)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundColor(tone.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.Radius.badge)
                .fill(Color.secondary.opacity(0.1)))
    }

    private func signalChip(_ network: NetworkModel) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cellularbars")
                .font(.system(size: 9, weight: .bold))
            Text(verbatim: "\(network.signal) dBm")
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DesignToken.Radius.badge)
                .fill(Color.secondary.opacity(0.1)))
    }

    private func fact(
        title: LocalizedStringKey, value: String, detail: String?, tone: ToolkitTone = .neutral
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(tone == .neutral ? .secondary : tone.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Helpers

    /// -100…-30 dBm mapped to 0…1 for the compact bar.
    private func levelFraction(for network: NetworkModel) -> Double {
        let clamped = min(max(Double(network.signal), -100), -30)
        return (clamped + 100) / 70
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

// MARK: - Whole-card hit target

/// Makes a dashboard card the navigation target itself: the whole card reacts
/// on hover and opens the tool on a click, instead of only the button in its
/// corner.
private struct DashboardLink: ViewModifier {
    let action: () -> Void
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .onTapGesture(perform: action)
            .onHover { isHovering = $0 }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(
                        isHovering ? Theme.Surface.tintStroke(.accentColor) : .clear,
                        lineWidth: 1.5
                    )
                    .allowsHitTesting(false)
            )
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    func dashboardLink(_ action: @escaping () -> Void) -> some View {
        modifier(DashboardLink(action: action))
    }
}
