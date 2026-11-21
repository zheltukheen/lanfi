import AppKit
import Charts
import SwiftUI
import LanFiCore

struct Iperf3ToolView: View {
    @ObservedObject var model: Iperf3ToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if !model.isInstalled {
                    installHint
                }
                if let error = model.errorMessage, model.isInstalled {
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
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToolTargetField(
                        text: $model.host, placeholder: "Server", maxWidth: 240,
                        onSubmit: { model.run() })
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
                        AppButton("Stop", tone: .secondary) { model.stop() }
                    } else {
                        AppButton("Run", tone: .primary) { model.run() }
                    }
                    AppButton("Copy", tone: .secondary) { copy() }
                        .disabled(model.report == nil)
                    AppButton("Clear", tone: .quiet) { model.clear() }
                        .disabled(model.report == nil)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                HStack(spacing: 14) {
                    Picker("Direction", selection: $model.direction) {
                        ForEach(Iperf3Direction.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 230)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("iperf3 is not installed")
                        .font(.caption.weight(.semibold))
                    Text(
                        "Install it with one click. LanFi uses Homebrew and enables Run as soon as the client is available."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
                if model.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    AppButton(
                        model.installSucceeded == false ? "Try Again" : "Install iperf3",
                        systemImage: "arrow.down.circle", tone: .primary
                    ) {
                        model.install()
                    }
                }
            }
            if let output = model.installOutput, !output.isEmpty {
                Text(output)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(model.installSucceeded == true ? .secondary : .orange)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                AppButton("Copy brew command", tone: .quiet) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        ToolInstaller.command(for: "iperf3"), forType: .string)
                }
                Text("Homebrew is required; a server must run on the target.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(DesignToken.Spacing.compact)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Measuring…") }
        guard let report = model.report else { return String(localized: "Ready") }
        return report.headlineMegabitsPerSecond.map { String(format: "%.0f Mbps", $0) }
            ?? String(localized: "Done")
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
                    AppButton("Clear history", tone: .quiet) { model.clearHistory() }
                        .font(.caption2)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "when", title: "When", minWidth: 120,
                            value: { .number($0.testedAt.timeIntervalSince1970) }
                        ) { measurement in
                            Text(
                                measurement.testedAt.formatted(
                                    date: .abbreviated, time: .shortened)
                            )
                            .font(.caption2)
                        },
                        AppTableColumn(
                            id: "server", title: "Server", minWidth: 150,
                            value: { .text($0.host) }
                        ) { measurement in
                            Text("\(measurement.host):\(measurement.port)")
                                .font(.caption.monospaced())
                        },
                        AppTableColumn(
                            id: "direction", title: "Direction", minWidth: 90,
                            value: { .text($0.direction.title) }
                        ) { measurement in
                            Text(measurement.direction.title)
                                .font(.caption)
                        },
                        AppTableColumn(
                            id: "mbps", title: "Mbps", minWidth: 70,
                            value: { .number($0.headlineMegabitsPerSecond) }
                        ) { measurement in
                            Text(
                                measurement.headlineMegabitsPerSecond.map {
                                    String(format: "%.0f", $0)
                                } ?? "—"
                            )
                            .font(.caption.monospacedDigit())
                        },
                    ],
                    rows: model.history, initialKey: "when", ascending: false
                )
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
