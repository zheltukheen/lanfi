import AppKit
import Charts
import SwiftUI

struct PingToolView: View {
    @ObservedObject var model: PingToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let stats = model.statistics {
                    metrics(stats)
                    if !stats.samples.isEmpty {
                        chart(stats)
                        samplesTable(stats)
                    }
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "dot.radiowaves.left.and.right",
                        title: "Ping a host",
                        message:
                            "ICMP or TCP probes, live round-trip times, loss and jitter. Try 1.1.1.1 or your router."
                    )
                }
            }
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ToolTargetField(text: $model.host, onSubmit: { model.run() })
                    Picker("Transport", selection: $model.transport) {
                        ForEach(PingTransport.allCases) { transport in
                            Text(transport.title).tag(transport)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 120)
                    if model.transport == .tcp {
                        TextField("Port", text: $model.portText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Menu {
                            Button("443 — HTTPS") { model.portText = "443" }
                            Button("80 — HTTP") { model.portText = "80" }
                            Button("22 — SSH") { model.portText = "22" }
                            Button("53 — DNS") { model.portText = "53" }
                            Button("8080 — HTTP Alt") { model.portText = "8080" }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Port presets")
                    }
                    Spacer()
                    if model.isRunning {
                        AppButton("Stop", tone: .secondary) { model.stop() }
                    } else {
                        AppButton("Run", tone: .primary) { model.run() }
                    }
                    AppButton("Copy", tone: .secondary) { copy() }
                        .disabled(model.statistics == nil)
                    AppButton("Clear", tone: .quiet) { model.clear() }
                        .disabled(model.samples.isEmpty)
                }
                HStack(spacing: 18) {
                    Stepper(value: $model.count, in: 1...10_000) {
                        Text("Probes: \(model.count)")
                            .font(.caption)
                    }
                    .fixedSize()
                    .disabled(model.continuous)
                    Toggle("Continuous", isOn: $model.continuous)
                        .font(.caption)
                        .fixedSize()
                    Stepper(value: $model.interval, in: 0.1...5, step: 0.1) {
                        Text(
                            String(
                                format: String(localized: "Interval: %.1f s"),
                                model.interval)
                        )
                        .font(.caption)
                    }
                    .fixedSize()
                    Spacer()
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Pinging…") }
        guard let stats = model.statistics else { return String(localized: "Ready") }
        return String(
            format: String(localized: "Replies: %lld/%lld · %lld%% loss"),
            stats.received, stats.transmitted, Int(stats.packetLossPercent))
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let stats = model.statistics else { return .neutral }
        if stats.received == 0 { return .bad }
        return stats.packetLossPercent > 0 ? .warning : .good
    }

    private func metrics(_ stats: PingStatistics) -> some View {
        ToolkitCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 105), spacing: 14)],
                alignment: .leading,
                spacing: 10
            ) {
                ToolkitMetric(title: "Minimum", value: ToolkitFormat.milliseconds(stats.minMilliseconds))
                ToolkitMetric(title: "Average", value: ToolkitFormat.milliseconds(stats.averageMilliseconds))
                ToolkitMetric(title: "Maximum", value: ToolkitFormat.milliseconds(stats.maxMilliseconds))
                ToolkitMetric(title: "Jitter", value: ToolkitFormat.milliseconds(stats.jitterMilliseconds))
                ToolkitMetric(
                    title: "Packet loss",
                    value: String(format: "%.0f%%", stats.packetLossPercent),
                    tint: stats.packetLossPercent > 0 ? .orange : .green)
                ToolkitMetric(title: "Replies", value: "\(stats.received)/\(stats.transmitted)")
            }
        }
    }

    private func chart(_ stats: PingStatistics) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Round trip")
                Chart {
                    ForEach(stats.samples) { sample in
                        if let rtt = sample.rttMilliseconds {
                            LineMark(
                                x: .value("Probe", sample.sequence),
                                y: .value("RTT", rtt)
                            )
                            .interpolationMethod(.monotone)
                            PointMark(
                                x: .value("Probe", sample.sequence),
                                y: .value("RTT", rtt)
                            )
                            .symbolSize(18)
                        }
                    }
                }
                .chartXAxis { chartAxis }
                .chartYAxis { chartAxis }
                .chartYAxisLabel("ms", position: .leading)
                .frame(height: 150)
            }
        }
    }

    private var chartAxis: some AxisContent {
        AxisMarks { _ in
            AxisGridLine(stroke: ChartStyle.gridStroke)
                .foregroundStyle(ChartStyle.gridColor)
            AxisValueLabel()
                .font(ChartStyle.axisLabelFont)
                .foregroundStyle(ChartStyle.axisLabelColor)
        }
    }

    private func samplesTable(_ stats: PingStatistics) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Probes")
                    Spacer()
                    Text("\(stats.samples.count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                // Column headers sort the table; the analyzer keeps its own
                // sort and filter controls.
                AppTable(columns: sampleColumns, rows: stats.samples, initialKey: "sequence")
                    .frame(height: min(CGFloat(stats.samples.count) * 24 + 28, 230))
            }
        }
    }

    private var sampleColumns: [AppTableColumn<PingSample>] {
        [
            AppTableColumn(
                id: "sequence", title: "#", minWidth: 44,
                value: { .number(Double($0.sequence)) },
                cell: { sample in
                    AnyView(
                        Text("\(sample.sequence)")
                            .font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "rtt", title: "Round trip", minWidth: 90,
                value: { .number($0.rttMilliseconds) },
                cell: { sample in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(sample.rttMilliseconds))
                            .font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "status", title: "Status", minWidth: 160,
                value: { .text($0.succeeded ? "1" : "0") },
                cell: { sample in
                    AnyView(
                        Text(
                            sample.succeeded
                                ? String(localized: "Reply")
                                : (sample.error ?? String(localized: "No reply"))
                        )
                        .font(.caption)
                        .foregroundColor(sample.succeeded ? .secondary : .orange))
                }),
        ]
    }

    private func copy() {
        guard let stats = model.statistics else { return }
        var lines = [
            "LanFi ping \(stats.host)",
            "Transmitted \(stats.transmitted), received \(stats.received), loss \(String(format: "%.0f", stats.packetLossPercent))%",
            "min \(ToolkitFormat.milliseconds(stats.minMilliseconds)) · avg \(ToolkitFormat.milliseconds(stats.averageMilliseconds)) · max \(ToolkitFormat.milliseconds(stats.maxMilliseconds)) · jitter \(ToolkitFormat.milliseconds(stats.jitterMilliseconds))",
            "",
        ]
        for sample in stats.samples {
            lines.append(
                "\(sample.sequence)\t\(ToolkitFormat.milliseconds(sample.rttMilliseconds))\t\(sample.succeeded ? "reply" : (sample.error ?? "no reply"))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
