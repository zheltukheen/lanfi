import AppKit
import Charts
import LanFiCore
import SwiftUI
import UniformTypeIdentifiers

/// Rolling view of the connected Wi-Fi link. Samples are intentionally
/// separated from the scan table: the table answers "what is around me now",
/// this view answers "what happened over the last hours".
struct MonitorView: View {
    @ObservedObject var monitor: MonitorViewModel
    @State private var showingClear = false
    @State private var showingAlerts = false
    @State private var comparisonWindow: ComparisonWindow = .hour
    @State private var exportError: String?

    private enum ComparisonWindow: String, CaseIterable, Identifiable {
        case hour
        case sixHours
        case day

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hour: return "1 h"
            case .sixHours: return "6 h"
            case .day: return "24 h"
            }
        }

        var interval: TimeInterval {
            switch self {
            case .hour: return 60 * 60
            case .sixHours: return 6 * 60 * 60
            case .day: return 24 * 60 * 60
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if monitor.samples.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        currentLink
                        statisticsRow
                        reliabilityCard
                        comparisonRow
                        chart
                        peerList
                        events
                        Text(
                            "Sampling every \(Int(monitor.retention.sampleInterval)) s · stored locally in Application Support"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(DesignToken.Spacing.medium)
                }
            }
        }
        .sheet(isPresented: $showingAlerts) {
            MonitorAlertSettingsView(monitor: monitor)
        }
        .alert("Clear monitor history?", isPresented: $showingClear) {
            Button("Clear", role: .destructive) { monitor.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every sample and event. It cannot be undone.")
        }
        .alert(
            "Could not export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("Wi-Fi Monitor", systemImage: "waveform.path.ecg.rectangle")
                .font(.headline)

            Toggle("Record", isOn: $monitor.isRecording)
                .toggleStyle(.switch)
                .controlSize(.small)

            Picker("Keep", selection: $monitor.retention) {
                ForEach(MonitorRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Spacer()

            if let last = monitor.lastSample {
                Text("\(last.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Button {
                showingAlerts = true
            } label: {
                Image(systemName: monitor.alerts.anyEnabled ? "bell.badge" : "bell")
            }
            .help("Monitor alerts")
            .accessibilityLabel("Monitor alerts")
            Menu {
                Button("Connected samples…") { exportCSV(peers: false) }
                Button("Visible networks…") { exportCSV(peers: true) }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(monitor.samples.isEmpty && monitor.peers.isEmpty)
            Button("Clear") { showingClear = true }
                .disabled(monitor.samples.isEmpty)
        }
        .padding(.horizontal, DesignToken.Spacing.medium)
        .padding(.vertical, DesignToken.Spacing.small)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("No samples yet")
                .font(.headline)
            Text(
                "Turn on Record and keep LanFi running. The connected link is sampled once per \(Int(monitor.retention.sampleInterval)) seconds, with roaming, channel and security events."
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignToken.Spacing.section)
    }

    @ViewBuilder
    private var currentLink: some View {
        if let last = monitor.lastSample {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(last.ssid.isEmpty ? "Hidden network" : last.ssid)
                        .font(.title3.bold())
                    Text(
                        "\(last.bssid) · \(last.band) · channel \(last.channel) · \(last.security)"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                }
                Spacer()
                Text("\(last.rssi) dBm")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundColor(color(for: last.rssi))
            }
        }
    }

    @ViewBuilder
    private var statisticsRow: some View {
        if let stats = monitor.statistics {
            HStack(spacing: 18) {
                statistic("Min", value: "\(stats.minimum) dBm")
                statistic("Avg", value: "\(stats.averageRounded) dBm")
                statistic("Max", value: "\(stats.maximum) dBm")
                statistic("p95", value: "\(stats.p95) dBm")
                statistic("Samples", value: "\(stats.count)")
                Spacer()
            }
            .padding(DesignToken.Spacing.compact)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.control))
        }
    }

    /// G10: a verdict over the recorded window instead of a timeline the reader
    /// has to interpret themselves.
    private var reliabilityCard: some View {
        let assessment = monitor.reliability
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reliability").font(.headline)
                Spacer()
                Text(assessment.grade.title)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, DesignToken.Spacing.tight)
                    .padding(.vertical, 2)
                    .background(
                        DesignToken.Surface.tintFill(color(for: assessment.grade)), in: Capsule())
            }

            if let score = assessment.score {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(color(for: assessment.grade))
                    Text("out of 100")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(observationLabel(assessment))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if assessment.weakSampleShare > 0 {
                    Text(
                        String(
                            format: String(localized: "Weak signal for %lld%% of samples"),
                            Int((assessment.weakSampleShare * 100).rounded()))
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                if assessment.problems.isEmpty {
                    Text("No disconnects, failed roams or weak stretches in this window.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(assessment.problems.prefix(6)) { problem in
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(problem.signal.title)
                                .font(.caption)
                            Spacer()
                            Text(problemRange(problem))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            Text("×\(problem.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("Not enough data yet")
                    .font(.caption.weight(.semibold))
                Text(
                    String(
                        format: String(
                            localized:
                                "A verdict needs at least %lld samples over %@; this window has %lld."
                        ), ReliabilityAssessor.minimumSamples,
                        durationText(ReliabilityAssessor.minimumObservation), assessment.sampleCount)
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignToken.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }

    private func observationLabel(_ assessment: ReliabilityAssessment) -> String {
        String(
            format: String(localized: "%lld samples over %@"), assessment.sampleCount,
            durationText(assessment.observedSeconds))
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total >= 3_600 { return "\(total / 3_600) h \(total % 3_600 / 60) min" }
        if total >= 60 { return "\(total / 60) min" }
        return "\(total) s"
    }

    private func problemRange(_ problem: ReliabilityProblem) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle =
            Calendar.current.isDate(problem.firstAt, inSameDayAs: problem.lastAt) ? .none : .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: problem.firstAt)) – \(formatter.string(from: problem.lastAt))"
    }

    private func color(for grade: ReliabilityGrade) -> Color {
        switch grade {
        case .good: return .green
        case .fair: return .orange
        case .poor: return .red
        case .insufficient: return .secondary
        }
    }

    private var comparisonRow: some View {
        let comparison = MonitorComparison(
            samples: monitor.samples, window: comparisonWindow.interval)
        return HStack(spacing: 8) {
            Text("Compare").font(.caption2).foregroundColor(.secondary)
            Picker("Compare", selection: $comparisonWindow) {
                ForEach(ComparisonWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
            .labelsHidden()
            .frame(width: 80)

            if let current = comparison.currentAverage,
                let previous = comparison.previousAverage,
                let delta = comparison.delta
            {
                Text("Avg \(current) vs \(previous) dBm")
                    .font(.caption.monospacedDigit())
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundColor(delta >= 0 ? .green : .red)
                Text("(\(comparison.currentSamples) vs \(comparison.previousSamples) samples)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Not enough history for the previous window.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var chart: some View {
        Chart(chartSamples) { sample in
            AreaMark(
                x: .value("Time", sample.at),
                y: .value("RSSI", sample.rssi)
            )
            .foregroundStyle(Color.accentColor.opacity(0.12))

            LineMark(
                x: .value("Time", sample.at),
                y: .value("RSSI", sample.rssi)
            )
            .foregroundStyle(Color.accentColor)
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: -100...(-30))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Connected network signal history")
        .accessibilityValue(monitor.lastSample.map { "Latest \($0.rssi) dBm" } ?? "")
    }

    private var peerList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Visible networks").font(.headline)
                Spacer()
                Text("\(monitor.peers.count)").font(.caption).foregroundColor(.secondary)
            }

            if monitor.peers.isEmpty {
                Text("No peer samples yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitor.peers.prefix(15)) { peer in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(peer.ssid.isEmpty ? "Hidden network" : peer.ssid)
                                .font(.caption.bold())
                            Text("\(peer.bssid) · \(peer.band) · channel \(peer.channel)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(peer.averageRSSI) dBm")
                                .font(.caption.monospacedDigit())
                            Text("min \(peer.rssiMin) · max \(peer.rssiMax) · \(peer.samples)×")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        if monitor.lastSample?.bssid == peer.bssid {
                            Image(systemName: "wifi")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                                .help("Connected network")
                        }
                    }
                }
                if monitor.peers.count > 15 {
                    Text("+\(monitor.peers.count - 15) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Events").font(.headline)
                Spacer()
                Text("\(monitor.events.count)").font(.caption).foregroundColor(.secondary)
            }

            if monitor.events.isEmpty {
                Text("No transitions recorded yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(monitor.events.suffix(40).reversed())) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: event.kind))
                            .foregroundColor(color(for: event.kind))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.kind.title).font(.caption.bold())
                            Text(event.detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Text(event.at.formatted(date: .omitted, time: .standard))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var chartSamples: [MonitorSample] {
        let samples = monitor.samples
        let maximum = 300
        guard samples.count > maximum else { return samples }
        let step = Double(samples.count) / Double(maximum)
        return (0..<maximum).map { samples[min(samples.count - 1, Int(Double($0) * step))] }
    }

    private func statistic(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func icon(for kind: MonitorEventKind) -> String {
        switch kind {
        case .connected: return "wifi"
        case .disconnected: return "wifi.slash"
        case .roamed: return "arrow.triangle.2.circlepath"
        case .channelChanged: return "antenna.radiowaves.left.and.right"
        case .securityChanged: return "lock.trianglebadge.exclamationmark"
        case .weakSignal: return "exclamationmark.triangle"
        case .deauthBurst: return "bolt.trianglebadge.exclamationmark"
        case .roamingFailure: return "arrow.triangle.2.circlepath.circle"
        case .gatewayChanged: return "exclamationmark.shield"
        case .dnsMismatch: return "questionmark.circle"
        case .vpnDropped: return "lock.slash"
        case .vpnLeak: return "lock.trianglebadge.exclamationmark"
        case .newAccessPoint: return "plus.circle"
        }
    }

    private func color(for kind: MonitorEventKind) -> Color {
        switch kind {
        case .connected: return .green
        case .disconnected: return .red
        case .roamed: return .blue
        case .channelChanged: return .orange
        case .securityChanged: return .red
        case .weakSignal: return .yellow
        case .deauthBurst: return .red
        case .roamingFailure: return .orange
        case .gatewayChanged: return .red
        case .dnsMismatch: return .orange
        case .vpnDropped: return .red
        case .vpnLeak: return .orange
        case .newAccessPoint: return .blue
        }
    }

    private func color(for rssi: Int) -> Color {
        if rssi >= -60 { return .green }
        if rssi >= -75 { return .orange }
        return .red
    }

    private func exportCSV(peers: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = peers ? "LanFi-monitor-networks.csv" : "LanFi-monitor.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let csv = peers ? monitor.peersCSV : monitor.csv
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
