import AppKit
import Charts
import SwiftUI

struct Iperf3ToolView: View {
    @ObservedObject var model: Iperf3ToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if !model.isInstalled {
                    installHint
                }
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.report {
                    metrics(report)
                    chart(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "arrow.up.arrow.down",
                        title: "Measure a link with iperf3",
                        message:
                            "Runs the Homebrew iperf3 client against your own server and parses its JSON report. This is not a public speed test."
                    )
                }
                if !model.history.isEmpty {
                    historySection
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Server", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    TextField("5201", text: $model.portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Menu {
                        if model.savedServers.isEmpty {
                            Text("No saved servers")
                        }
                        ForEach(model.savedServers) { server in
                            Menu(server.name) {
                                Button("Use") { model.applyServer(server) }
                                Button("Remove", role: .destructive) {
                                    model.removeServer(server)
                                }
                            }
                        }
                        Divider()
                        Button("Save current server") { model.saveCurrentServer() }
                    } label: {
                        Label("Saved servers", systemImage: "bookmark")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    if model.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Run") { model.run() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Copy") { copy() }
                        .buttonStyle(.bordered)
                        .disabled(model.report == nil)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.report == nil)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                HStack(spacing: 14) {
                    Picker("Direction", selection: $model.direction) {
                        ForEach(Iperf3Direction.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 470)
                    Stepper(value: $model.duration, in: 1...120) {
                        Text("\(model.duration) s")
                            .font(.caption)
                    }
                    .fixedSize()
                    Spacer()
                }
                Text(
                    "Needs an iperf3 server on the target. Nothing is measured against a third-party speed-test service."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private var installHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundColor(.orange)
            Text("iperf3 is not installed. Run `brew install iperf3` and reopen the toolkit.")
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Measuring…") }
        guard let report = model.report else { return String(localized: "Ready") }
        return report.headlineMegabitsPerSecond.map { String(format: "%.0f Mbps", $0) } ?? "Done"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        return model.report == nil ? .neutral : .good
    }

    private func metrics(_ report: Iperf3Report) -> some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(
                    title: "Headline",
                    value: report.headlineMegabitsPerSecond.map {
                        String(format: "%.0f Mbps", $0)
                    } ?? "—",
                    tint: .accentColor)
                ToolkitMetric(
                    title: "Sent",
                    value: report.sentMegabitsPerSecond.map {
                        String(format: "%.0f Mbps", $0)
                    } ?? "—")
                ToolkitMetric(
                    title: "Received",
                    value: report.receivedMegabitsPerSecond.map {
                        String(format: "%.0f Mbps", $0)
                    } ?? "—")
                ToolkitMetric(
                    title: "Duration",
                    value: report.durationSeconds.map { String(format: "%.0f s", $0) } ?? "—")
                ToolkitMetric(title: "Server", value: "\(report.host):\(report.port)")
            }
        }
    }

    private func chart(_ report: Iperf3Report) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Throughput")
                if report.intervals.isEmpty {
                    Text("iperf3 returned no interval samples.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Chart(report.intervals) { interval in
                        LineMark(
                            x: .value("Time", interval.end),
                            y: .value("Mbps", interval.megabitsPerSecond)
                        )
                        .interpolationMethod(.monotone)
                        PointMark(
                            x: .value("Time", interval.end),
                            y: .value("Mbps", interval.megabitsPerSecond)
                        )
                        .symbolSize(16)
                    }
                    .chartYAxisLabel("Mbps")
                    .frame(height: 190)
                }
            }
        }
    }

    private var historySection: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "History")
                    Spacer()
                    Button("Clear history") { model.clearHistory() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(model.newestFirst) {
                    TableColumn("When") { measurement in
                        Text(
                            measurement.testedAt.formatted(
                                date: .abbreviated, time: .shortened)
                        )
                        .font(.caption2)
                    }
                    TableColumn("Server") { measurement in
                        Text("\(measurement.host):\(measurement.port)")
                            .font(.caption.monospaced())
                    }
                    TableColumn("Direction") { measurement in
                        Text(measurement.direction.title)
                            .font(.caption)
                    }
                    .width(110)
                    TableColumn("Mbps") { measurement in
                        Text(
                            measurement.headlineMegabitsPerSecond.map {
                                String(format: "%.0f", $0)
                            } ?? "—"
                        )
                        .font(.caption.monospacedDigit())
                    }
                    .width(70)
                }
                .frame(height: min(CGFloat(model.history.count) * 26 + 40, 240))
            }
        }
    }

    private func copy() {
        guard let report = model.report else { return }
        let text = """
            LanFi iperf3 \(report.host):\(report.port) (\(report.direction.title))
            Headline: \(report.headlineMegabitsPerSecond.map { String(format: "%.1f Mbps", $0) } ?? "—")
            Sent: \(report.sentMegabitsPerSecond.map { String(format: "%.1f Mbps", $0) } ?? "—")
            Received: \(report.receivedMegabitsPerSecond.map { String(format: "%.1f Mbps", $0) } ?? "—")
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
