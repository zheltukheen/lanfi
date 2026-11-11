import SwiftUI

struct InternetCheckToolView: View {
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @ObservedObject var speedTest: SpeedTestToolModel
    @State private var mode: InternetCheckMode = .quick

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let report = diagnostics.report {
                    verdictCard(report)
                    pathCard(report)
                    evidenceCard(report)
                    if mode == .full, speedTest.isRunning {
                        ProgressView("Measuring speed…")
                            .frame(maxWidth: .infinity)
                    } else if mode == .full, let speed = speedTest.report {
                        speedCard(speed)
                    }
                } else if diagnostics.isRunning {
                    ProgressView("Running checks…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    ToolkitEmptyState(
                        icon: "stethoscope",
                        title: "Check the whole path",
                        message:
                            "Tests this Mac, the router, the internet, DNS and the web, then says where the problem most likely is."
                    )
                }
            }
            .padding(18)
        }
        .task {
            if diagnostics.report == nil {
                await diagnostics.run()
            }
        }
    }

    private func runCheck() async {
        await diagnostics.run()
        if mode == .full {
            await speedTest.measure()
        }
    }

    private func speedCard(_ report: ThroughputReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ToolkitSectionLabel(text: "Speed")
                    Spacer()
                    Text(report.testedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 20) {
                    ToolkitMetric(
                        title: "Download",
                        value: report.downloadMbps.map { String(format: "%.0f Mbps", $0) }
                            ?? "—")
                    ToolkitMetric(
                        title: "Upload",
                        value: report.uploadMbps.map { String(format: "%.0f Mbps", $0) }
                            ?? "—")
                    ToolkitMetric(
                        title: "Latency",
                        value: report.latencyMilliseconds.map {
                            String(format: "%.0f ms", $0)
                        } ?? "—")
                    ToolkitMetric(
                        title: "Responsiveness",
                        value: report.responsiveness.map { String(format: "%.0f RPM", $0) }
                            ?? "—")
                    Spacer()
                }
                if let error = speedTest.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Mode", selection: $mode) {
                        ForEach(InternetCheckMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)

                    Button {
                        Task { await runCheck() }
                    } label: {
                        Label(
                            mode == .full ? "Full Check" : "Quick Check",
                            systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(diagnostics.isRunning || speedTest.isRunning)

                    Toggle("Monitor every 60 s", isOn: $diagnostics.autoMonitor)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Spacer()

                    ToolkitStatusPill(
                        text: diagnostics.report?.verdict.title ?? "Not run yet",
                        tone: diagnostics.report.map { tone(for: $0.verdict) } ?? .neutral)
                }
                HStack(spacing: 10) {
                    Text(diagnostics.lastRunText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Copy") { diagnostics.copyReport() }
                        .buttonStyle(.bordered)
                        .disabled(diagnostics.report == nil)
                }
            }
        }
    }

    private func verdictCard(_ report: DiagnosticsReport) -> some View {
        let verdict = report.verdict
        let color = tone(for: verdict).color
        return ToolkitCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon(for: verdict))
                    .font(.system(size: 38))
                    .foregroundColor(color)
                    .frame(width: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(verdict.title)
                        .font(.title3.bold())
                    Text(verdict.detail)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !report.verdictEvidence.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(report.verdictEvidence.prefix(3)) { check in
                                Text("\(check.title): \(check.value)")
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding(.top, 2)
                    }
                    if report.warningCount > 0 {
                        Text(
                            String(
                                format: String(localized: "%lld warnings"),
                                report.warningCount)
                        )
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
                Spacer()
            }
            .padding(4)
            .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func pathCard(_ report: DiagnosticsReport) -> some View {
        let nodes = pathNodes(report)
        return ToolkitCard {
            VStack(alignment: .leading, spacing: 12) {
                ToolkitSectionLabel(text: "Path")
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                        nodeView(node)
                        if index < nodes.count - 1 {
                            connector(from: node.status, to: nodes[index + 1].status)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 21)
                        }
                    }
                }
            }
        }
    }

    private func evidenceCard(_ report: DiagnosticsReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ToolkitSectionLabel(text: "Details")
                    Spacer()
                    Text(report.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ForEach(report.verdictEvidence) { check in
                    checkRow(check)
                }
                if report.checks.count > report.verdictEvidence.count {
                    DisclosureGroup("All \(report.checks.count) checks") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(report.checks) { check in
                                checkRow(check)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func checkRow(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon(for: check.status))
                .font(.caption)
                .foregroundColor(tone(for: check.status).color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.title)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(check.value)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Text(check.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let recommendation = check.recommendation {
                    Text(recommendation)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Path

    private struct PathNode {
        let title: String
        let value: String
        let status: DiagnosticStatus
        let icon: String
    }

    private func pathNodes(_ report: DiagnosticsReport) -> [PathNode] {
        let thisMacStatus: DiagnosticStatus =
            check("wifi-link", in: report)?.status == .fail
                || check("ipv4", in: report)?.status == .fail ? .fail : .pass
        return [
            PathNode(
                title: String(localized: "This Mac"),
                value: report.snapshot.ssid ?? "Wi-Fi",
                status: thisMacStatus,
                icon: "laptopcomputer"),
            PathNode(
                title: String(localized: "Router"),
                value: check("gateway", in: report)?.value ?? "—",
                status: check("gateway", in: report)?.status ?? .pending,
                icon: "wifi.router"),
            PathNode(
                title: String(localized: "Internet"),
                value: check("latency", in: report)?.value ?? "—",
                status: check("latency", in: report)?.status ?? .pending,
                icon: "globe"),
            PathNode(
                title: String(localized: "DNS"),
                value: check("dns", in: report)?.value ?? "—",
                status: check("dns", in: report)?.status ?? .pending,
                icon: "server.rack"),
            PathNode(
                title: String(localized: "Web"),
                value: check("internet", in: report)?.value ?? "—",
                status: check("internet", in: report)?.status ?? .pending,
                icon: "safari"),
        ]
    }

    private func nodeView(_ node: PathNode) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(tone(for: node.status).color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: node.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(tone(for: node.status).color)
            }
            Text(node.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(node.value)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
        .frame(width: 104)
    }

    private func connector(from left: DiagnosticStatus, to right: DiagnosticStatus) -> some View {
        Rectangle()
            .fill(connectorColor(left: left, right: right))
            .frame(height: 2)
    }

    private func connectorColor(left: DiagnosticStatus, right: DiagnosticStatus) -> Color {
        if right == .fail { return .red.opacity(0.7) }
        if left == .pass, right == .pass { return .green.opacity(0.7) }
        return .secondary.opacity(0.25)
    }

    private func check(_ id: String, in report: DiagnosticsReport) -> DiagnosticCheck? {
        report.checks.first { $0.id == id }
    }

    // MARK: - Status mapping

    private func tone(for verdict: DiagnosticVerdict) -> ToolkitTone {
        verdict.isProblem ? .bad : .good
    }

    private func tone(for status: DiagnosticStatus) -> ToolkitTone {
        switch status {
        case .pass: return .good
        case .warning: return .warning
        case .fail: return .bad
        case .running: return .running
        case .pending, .skipped: return .neutral
        }
    }

    private func icon(for verdict: DiagnosticVerdict) -> String {
        switch verdict {
        case .healthy: return "checkmark.circle.fill"
        case .localNetwork: return "wifi.exclamationmark"
        case .router: return "wifi.router"
        case .provider: return "network"
        case .dns: return "server.rack"
        case .web: return "safari"
        }
    }

    private func icon(for status: DiagnosticStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .pending, .skipped: return "minus.circle"
        }
    }
}

private enum InternetCheckMode: String, CaseIterable, Identifiable {
    case quick, full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return String(localized: "Quick")
        case .full: return String(localized: "Full")
        }
    }
}
