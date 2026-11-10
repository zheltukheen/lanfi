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
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Host", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
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
                    }
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
                        .disabled(model.statistics == nil)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.samples.isEmpty)
                }
                HStack(spacing: 18) {
                    Stepper(value: $model.count, in: 1...10_000) {
                        Text("Probes: \(model.count)")
                            .font(.caption)
                    }
                    .fixedSize()
                    Stepper(value: $model.interval, in: 0.1...5, step: 0.1) {
                        Text("Interval: \(String(format: "%.1f", model.interval)) s")
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
        if model.isRunning { return "Pinging…" }
        guard let stats = model.statistics else { return "Ready" }
        return "\(stats.received)/\(stats.transmitted) replies · \(Int(stats.packetLossPercent))% loss"
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
                .chartYAxisLabel("ms")
                .frame(height: 150)
            }
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
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(stats.samples) {
                    TableColumn("#") { sample in
                        Text("\(sample.sequence)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(44)
                    TableColumn("Round trip") { sample in
                        Text(ToolkitFormat.milliseconds(sample.rttMilliseconds))
                            .font(.caption.monospacedDigit())
                    }
                    .width(110)
                    TableColumn("Status") { sample in
                        Text(sample.succeeded ? "Reply" : (sample.error ?? "No reply"))
                            .font(.caption)
                            .foregroundColor(sample.succeeded ? .secondary : .orange)
                    }
                }
                .frame(height: min(CGFloat(stats.samples.count) * 24 + 28, 230))
            }
        }
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
