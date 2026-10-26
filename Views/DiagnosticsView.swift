import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @State private var throughput: ThroughputReport?
    @State private var throughputRunning = false
    @State private var throughputError: String?

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let report = diagnostics.report {
                    scoreStrip(report)
                    snapshotStrip(report.snapshot)
                    checkGrid(report)
                    throughputSection
                    historyStrip
                } else {
                    emptyState
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            if diagnostics.report == nil {
                await diagnostics.run()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(diagnostics.overall).opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: statusIcon(diagnostics.overall))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(statusColor(diagnostics.overall))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Network diagnostics")
                    .font(.headline)
                Text(diagnostics.lastRunText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("Monitor every 60 s", isOn: $diagnostics.autoMonitor)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                Task { await diagnostics.run() }
            } label: {
                if diagnostics.isRunning {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Label("Run", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(diagnostics.isRunning)

            Button {
                diagnostics.copyReport()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy diagnostics report")
            .accessibilityLabel("Copy diagnostics report")
            .disabled(diagnostics.report == nil)

            Button {
                DiagnosticsBundleExporter.exportWithPanel(
                    report: diagnostics.report,
                    history: diagnostics.history,
                    interfaces: nil
                )
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export diagnostics bundle")
            .accessibilityLabel("Export diagnostics bundle")
        }
    }

    private func snapshotStrip(_ snapshot: LinkSnapshot) -> some View {
        HStack(spacing: 0) {
            snapshotItem("Wi-Fi", value: snapshot.ssid ?? "—", icon: "wifi")
            divider
            snapshotItem("RSSI", value: snapshot.rssi.map { "\($0) dBm" } ?? "—", icon: "waveform")
            divider
            snapshotItem(
                "Link rate",
                value: snapshot.transmitRateMbps.map { String(format: "%.0f Mbps", $0) } ?? "—",
                icon: "speedometer"
            )
            divider
            snapshotItem("Router", value: snapshot.router ?? "—", icon: "arrow.triangle.branch")
            divider
            snapshotItem("DNS", value: snapshot.dnsServers.first ?? "—", icon: "server.rack")
            divider
            snapshotItem("IPv4", value: snapshot.primaryIPv4 ?? "—", icon: "network")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private var divider: some View {
        Divider().frame(height: 26).padding(.horizontal, 8)
    }

    private func snapshotItem(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption2).foregroundColor(.secondary)
                Text(value).font(.caption).lineLimit(1)
            }
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private func checkGrid(_ report: DiagnosticsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(DiagnosticCategory.allCases) { category in
                let checks = report.checks.filter { $0.category == category }
                if !checks.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(category.title, systemImage: category.systemImage)
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(checks) { check in
                                checkCard(check)
                            }
                        }
                    }
                }
            }
        }
    }

    private func scoreStrip(_ report: DiagnosticsReport) -> some View {
        HStack(spacing: 10) {
            Text("\(report.healthScore)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(statusColor(report.overall))
            VStack(alignment: .leading, spacing: 1) {
                Text("Network health").font(.caption.bold())
                Text("\(report.passedCount) passed · \(report.warningCount) warnings · \(report.failedCount) failed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(report.checks.count) checks · \(Int(report.duration * 1000)) ms")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func checkCard(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon(check.status))
                .foregroundColor(statusColor(check.status))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(check.title)).font(.caption.bold())
                    Spacer()
                    Text(check.status.label)
                        .font(.caption2.bold())
                        .foregroundColor(statusColor(check.status))
                }
                Text(TechnicalLocalizer.localize(check.value))
                    .font(.caption)
                    .lineLimit(1)
                Text(TechnicalLocalizer.localize(check.detail))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                if let recommendation = check.recommendation {
                    Text(TechnicalLocalizer.localize(recommendation))
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor(check.status).opacity(0.2), lineWidth: 1)
        )
    }

    private var throughputSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Throughput")
                    .font(.caption.bold())
                Spacer()
                Button {
                    runThroughput()
                } label: {
                    if throughputRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Run speed test")
                    }
                }
                .controlSize(.small)
                .disabled(throughputRunning)
            }
            if let throughput {
                HStack(spacing: 16) {
                    metric("Download", throughput.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                    metric("Upload", throughput.uploadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                    metric("Latency", throughput.latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                    metric("Responsiveness", throughput.responsiveness.map { String(format: "%.0f", $0) } ?? "—")
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let throughputError {
                Text(throughputError).font(.caption).foregroundColor(.red)
            } else {
                Text("Runs Apple networkQuality; it uploads/downloads test traffic for up to 20 seconds.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.bold())
        }
    }

    private func runThroughput() {
        throughputRunning = true
        throughputError = nil
        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try await ThroughputTester.run()
                }.value
                await MainActor.run {
                    throughputRunning = false
                    throughput = report
                }
            } catch {
                await MainActor.run {
                    throughputRunning = false
                    throughputError = error.localizedDescription
                }
            }
        }
    }

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent runs").font(.caption.bold())
            HStack(spacing: 4) {
                ForEach(diagnostics.history.suffix(12)) { historyItem in
                    Button {
                        diagnostics.selectHistory(historyItem)
                    } label: {
                        Capsule()
                            .fill(statusColor(historyItem.overall).opacity(0.7))
                            .frame(width: 18, height: 7)
                    }
                    .buttonStyle(.plain)
                    .help(
                        "\(historyItem.startedAt.formatted(date: .omitted, time: .standard)) · \(historyItem.summary)")
                }
                Spacer()
                Button("Clear") { diagnostics.clearHistory() }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .disabled(diagnostics.history.isEmpty)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.35))
            Text("Run a full network check")
                .font(.headline)
            Text("Wi-Fi radio, link, IPv4, gateway, DNS, captive portal, internet access and latency.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Run Diagnostics") {
                Task { await diagnostics.run() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func statusColor(_ status: DiagnosticStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        case .running, .pending: return .blue
        case .skipped: return .gray
        }
    }

    private func statusIcon(_ status: DiagnosticStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .pending: return "stethoscope"
        case .skipped: return "minus.circle"
        }
    }
}
