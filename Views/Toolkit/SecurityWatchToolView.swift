import SwiftUI

/// Security Watch (P1.1): one screen for evil-twin and downgrade heuristics on
/// live beacons, plus deauth bursts observed by packet capture. Read-only.
struct SecurityWatchToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel
    @ObservedObject var monitor: MonitorViewModel
    @StateObject private var gatewayGuard = GatewayGuard.shared

    private var report: SecurityWatchReport {
        SecurityWatchEvaluator.evaluate(networks: analyzer.networks, events: monitor.events)
    }

    private var deauthEvents: [MonitorEvent] {
        let cutoff = Date().addingTimeInterval(-SecurityWatchEvaluator.deauthWindow)
        return monitor.events
            .filter { $0.kind == .deauthBurst && $0.at >= cutoff }
            .suffix(20)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                integrityCard
                if report.alerts.isEmpty {
                    cleanState
                } else {
                    alertList
                }
                deauthCard
                methodology
            }
            .appContentPadding()
        }
    }

    private var summary: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ToolkitSectionLabel(text: "Watch summary")
                    Spacer()
                    ToolkitStatusPill(
                        text: report.alerts.isEmpty ? "No alerts" : "\(report.alerts.count) alerts",
                        tone: report.alerts.isEmpty ? .good : .bad)
                }
                HStack(spacing: 24) {
                    ToolkitMetric(
                        title: "Networks", value: "\(report.networkCount)", tint: .primary)
                    ToolkitMetric(
                        title: "SSIDs", value: "\(report.ssidCount)", tint: .primary)
                    ToolkitMetric(
                        title: "Critical", value: "\(report.criticalCount)",
                        tint: report.criticalCount > 0 ? AppPalette.danger : .secondary)
                    ToolkitMetric(
                        title: "Warnings", value: "\(report.warningCount)",
                        tint: report.warningCount > 0 ? AppPalette.warning : .secondary)
                    ToolkitMetric(
                        title: "SSIDs with alerts", value: "\(report.monitoredSSIDCount)",
                        tint: .primary)
                    Spacer()
                }
                Text(
                    "Heuristics over the current beacon scan: SSID groups that mix security levels, and BSSIDs with randomized addresses next to registered ones."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    /// P3.7: the below-Wi-Fi checks — gateway ARP and resolver answers.
    private var integrityCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Gateway and DNS integrity")
                    if gatewayGuard.isSampling { ProgressView().controlSize(.mini) }
                    Spacer()
                    if let at = gatewayGuard.lastCheckedAt {
                        Text("Last checked \(at.formatted(date: .omitted, time: .standard))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Button("Check now") {
                        Task { await gatewayGuard.sampleNow() }
                    }
                    .controlSize(.small)
                    .disabled(gatewayGuard.isSampling)
                }
                HStack(spacing: 24) {
                    ToolkitMetric(
                        title: "Gateway", value: gatewayGuard.gatewayIP ?? "—", tint: .primary)
                    ToolkitMetric(
                        title: "MAC", value: gatewayGuard.gatewayMAC ?? "—",
                        tint: gatewayGuard.macChangeCount > 0 ? AppPalette.danger : .primary)
                    ToolkitMetric(
                        title: "DNS", value: resolverLabel, tint: resolverTint)
                    Spacer()
                }
                Text(gatewayGuard.resolverCheck.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var resolverLabel: String {
        switch gatewayGuard.resolverCheck.verdict {
        case .match: return String(localized: "Match")
        case .mismatch: return String(localized: "Mismatch")
        case .unknown: return String(localized: "Not checked yet")
        }
    }

    private var resolverTint: Color {
        switch gatewayGuard.resolverCheck.verdict {
        case .match: return AppPalette.ok
        case .mismatch: return AppPalette.warning
        case .unknown: return .secondary
        }
    }

    private var cleanState: some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundColor(AppPalette.ok)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No twin or downgrade signatures in this scan").font(.callout.bold())
                    Text(
                        "Every SSID currently in range advertises one consistent security level, and no BSSID pair looks like a weaker copy. This checks beacons only — it cannot see a twin that is not beaconing yet."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    private var alertList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(report.alerts) { alert in
                alertRow(alert)
            }
        }
    }

    private func alertRow(_ alert: SecurityWatchAlert) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: alert.kind.icon)
                    .font(.title3)
                    .foregroundColor(tint(for: alert.severity))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(alert.kind.title).font(.callout.bold())
                        Text(alert.severity.label)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, DesignToken.Spacing.tight)
                            .padding(.vertical, 1)
                            .background(
                                tint(for: alert.severity).opacity(0.12), in: Capsule())
                    }
                    Text("\(alert.ssid) · \(alert.bssid)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                    Text(alert.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let network = analyzer.networks.first(where: {
                    $0.bssid.caseInsensitiveCompare(alert.bssid) == .orderedSame
                }) {
                    Button("Show") {
                        analyzer.selectedNetworkId = network.id
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var deauthCard: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Live deauth")
                    Spacer()
                    Text("\(deauthEvents.count) in 15 min")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                if deauthEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "No deauthentication burst recorded. macOS gives normal apps no passive deauth feed, so this appears only after a packet capture (Capture tab → Analyze capture)."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Button {
                            NotificationCenter.default.post(
                                name: .lanfiShowToolkit, object: nil,
                                userInfo: ["tool": ToolboxTool.wifiAnalyzer.rawValue])
                            NotificationCenter.default.post(
                                name: .lanfiSelectBottomTab, object: nil, userInfo: ["tab": 7])
                        } label: {
                            Label("Open Capture", systemImage: "record.circle")
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, DesignToken.Spacing.card)
                    .padding(.bottom, DesignToken.Spacing.card)
                } else {
                    ForEach(Array(deauthEvents.reversed())) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "bolt.trianglebadge.exclamationmark")
                                .foregroundColor(AppPalette.danger)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.detail).font(.caption2)
                                Text(
                                    "\(event.ssid.isEmpty ? "unknown SSID" : event.ssid) · \(event.bssid) · \(event.at.formatted(date: .abbreviated, time: .standard))"
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.vertical, 3)
                    }
                    .padding(.bottom, DesignToken.Spacing.compact)
                }
            }
        }
    }

    private var methodology: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 5) {
                ToolkitSectionLabel(text: "What this checks")
                Text(
                    "Evil twin: the same SSID is advertised with a lower security class (open or WEP) than another BSSID of that SSID, and the weaker radio is not an inferred co-located radio of the stronger one. Downgrade: the same pattern with WPA/WPA2. Randomized BSSID: a locally administered address next to registered hardware addresses for one SSID. Deauth: a captured burst from the Wi-Fi Monitor."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Below Wi-Fi: the default gateway's MAC is re-read from the ARP table every 2 minutes, and every 10 minutes the system resolver's answer for a canary host is compared with Cloudflare's direct answer. Both are warnings, not proof: a CDN legitimately varies by resolver."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "These are heuristics, not proof. LanFi never frames, injects or deauthenticates; confirm a suspected twin against your controller's AP list."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tint(for severity: IssueSeverity) -> Color {
        switch severity {
        case .critical: return AppPalette.danger
        case .warning: return AppPalette.warning
        case .info: return AppPalette.info
        }
    }
}
