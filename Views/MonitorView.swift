import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// Rolling view of the connected Wi-Fi link. Samples are intentionally
/// separated from the scan table: the table answers "what is around me now",
/// this view answers "what happened over the last hours".
struct MonitorView: View {
    @ObservedObject var monitor: MonitorViewModel
    @State private var showingClear = false
    @State private var exportError: String?

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
                        chart
                        events
                        Text(
                            "Sampling every \(Int(monitor.retention.sampleInterval)) s · stored locally in Application Support"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(12)
                }
            }
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

            Button("Export CSV") { exportCSV() }
                .disabled(monitor.samples.isEmpty)
            Button("Clear") { showingClear = true }
                .disabled(monitor.samples.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .padding(24)
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
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        }
    }

    private func color(for rssi: Int) -> Color {
        if rssi >= -60 { return .green }
        if rssi >= -75 { return .orange }
        return .red
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi-monitor.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try monitor.csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
