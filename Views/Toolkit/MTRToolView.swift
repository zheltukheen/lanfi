import AppKit
import SwiftUI

struct MTRToolView: View {
    @ObservedObject var model: MTRToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.report {
                    summary(report)
                    hopsTable(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Watch a route over time",
                        message:
                            "Repeats traceroute and aggregates loss and jitter per hop. Slower than a single trace, but shows which router is actually flaky."
                    )
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Host", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 230)
                    Stepper(value: $model.rounds, in: 1...100) {
                        Text("Rounds: \(model.rounds)")
                            .font(.caption)
                    }
                    .fixedSize()
                    Stepper(value: $model.maxHops, in: 1...64) {
                        Text("Max hops: \(model.maxHops)")
                            .font(.caption)
                    }
                    .fixedSize()
                    Spacer()
                    if model.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Start") { model.run() }
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
                Text("One traceroute probe per hop per round; loss and jitter are aggregated across rounds.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusText: String {
        if model.isRunning {
            return "Round \(model.report?.rounds ?? 0)/\(model.rounds)"
        }
        guard let report = model.report else { return "Ready" }
        return "\(report.rounds) rounds · \(report.hops.count) hops"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let report = model.report else { return .neutral }
        return report.reachedTarget ? .good : .warning
    }

    private func summary(_ report: MTRReport) -> some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(title: "Target", value: report.host)
                ToolkitMetric(title: "Rounds", value: "\(report.rounds)")
                ToolkitMetric(title: "Hops", value: "\(report.hops.count)")
                ToolkitMetric(
                    title: "Worst loss",
                    value: String(
                        format: "%.0f%%",
                        report.hops.map(\.lossPercent).max() ?? 0),
                    tint: (report.hops.map(\.lossPercent).max() ?? 0) > 0 ? .orange : .green)
                ToolkitMetric(
                    title: "Worst jitter",
                    value: ToolkitFormat.milliseconds(
                        report.hops.compactMap(\.jitterMilliseconds).max()))
            }
        }
    }

    private func hopsTable(_ report: MTRReport) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Hops")
                    Spacer()
                    Text(report.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(report.hops) {
                    TableColumn("Hop") { hop in
                        Text("\(hop.hop)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(38)
                    TableColumn("Address") { hop in
                        Text(hop.address ?? "*")
                            .font(.caption.monospaced())
                            .foregroundColor(hop.address == nil ? .secondary : .primary)
                    }
                    TableColumn("Loss") { hop in
                        Text(String(format: "%.0f%%", hop.lossPercent))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(hop.lossPercent > 0 ? .orange : .secondary)
                    }
                    .width(52)
                    TableColumn("Sent") { hop in
                        Text("\(hop.sent)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(44)
                    TableColumn("Last") { hop in
                        Text(ToolkitFormat.milliseconds(hop.lastMilliseconds))
                            .font(.caption.monospacedDigit())
                    }
                    .width(72)
                    TableColumn("Avg") { hop in
                        Text(ToolkitFormat.milliseconds(hop.averageMilliseconds))
                            .font(.caption.monospacedDigit())
                    }
                    .width(72)
                    TableColumn("Best") { hop in
                        Text(ToolkitFormat.milliseconds(hop.bestMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(72)
                    TableColumn("Worst") { hop in
                        Text(ToolkitFormat.milliseconds(hop.worstMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(72)
                    TableColumn("Jitter") { hop in
                        Text(ToolkitFormat.milliseconds(hop.jitterMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(72)
                }
                .frame(height: min(CGFloat(report.hops.count) * 26 + 40, 460))
            }
        }
    }

    private func copy() {
        guard let report = model.report else { return }
        var lines = ["LanFi MTR \(report.host) · \(report.rounds) rounds", ""]
        for hop in report.hops {
            lines.append(
                "\(hop.hop)\t\(hop.address ?? "*")\tloss \(String(format: "%.0f", hop.lossPercent))%\tsent \(hop.sent)\tavg \(ToolkitFormat.milliseconds(hop.averageMilliseconds))\tjitter \(ToolkitFormat.milliseconds(hop.jitterMilliseconds))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
