import AppKit
import SwiftUI
import LanFiCore

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
                    latencyChart(report)
                    hopsTable(report)
                } else if model.isRunning {
                    measuringCard
                } else {
                    ToolkitEmptyState(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Watch a route over time",
                        message:
                            "Repeats traceroute and aggregates loss and jitter per hop. Slower than a single trace, but shows which router is actually flaky."
                    )
                }
            }
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToolTargetField(text: $model.host, maxWidth: 230, onSubmit: { model.run() })
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
                    Toggle("Continuous", isOn: $model.continuous)
                        .font(.caption)
                    Spacer()
                    if model.isRunning {
                        AppButton("Stop", tone: .secondary) { model.stop() }
                    } else {
                        AppButton("Start", tone: .primary) { model.run() }
                    }
                    AppButton("Copy", tone: .secondary) { copy() }
                        .disabled(model.report == nil)
                    AppButton("Clear", tone: .quiet) { model.clear() }
                        .disabled(model.report == nil)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                Text("One traceroute probe per hop per round; loss and jitter are aggregated across rounds.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The first batch of rounds can take half a minute on a long route; an
    /// empty state here read as "nothing is happening".
    private var measuringCard: some View {
        ToolkitCard {
            HStack(spacing: DesignToken.Spacing.medium) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Measuring the route…")
                        .font(.caption.weight(.semibold))
                    Text(
                        "Each round is one traceroute probe per hop. The chart appears after the first round."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private var statusText: String {
        if model.isRunning {
            return String(
                format: String(localized: "Round %lld/%lld"),
                model.report?.rounds ?? 0, model.rounds)
        }
        guard let report = model.report else { return String(localized: "Ready") }
        return String(
            format: String(localized: "%lld rounds · %lld hops"),
            report.rounds, report.hops.count)
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

    private func latencyChart(_ report: MTRReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ToolkitSectionLabel(text: "Latency and loss by hop")
                    Spacer()
                    chartLegendItem(color: .accentColor, text: "Avg latency")
                    chartLegendItem(color: .orange, text: "Loss")
                }
                if report.hops.isEmpty {
                    Text("No hops yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    MTRHopChart(hops: report.hops)
                }
            }
        }
    }

    private func chartLegendItem(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 3)
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
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
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                // Column headers sort the table; the analyzer keeps its own
                // sort and filter controls.
                AppTable(columns: hopColumns, rows: report.hops, initialKey: "hop")
                    .frame(height: min(CGFloat(report.hops.count) * 26 + 52, 500))
            }
        }
    }

    private var hopColumns: [AppTableColumn<MTRHop>] {
        [
            AppTableColumn(
                id: "hop", title: "Hop", minWidth: 40,
                value: { .number(Double($0.hop)) },
                cell: { hop in
                    AnyView(Text("\(hop.hop)").font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "address", title: "Address", minWidth: 130,
                value: { .text($0.address) },
                cell: { hop in
                    AnyView(
                        Text(hop.address ?? "*")
                            .font(.caption.monospaced())
                            .foregroundColor(hop.address == nil ? .secondary : .primary))
                }),
            AppTableColumn(
                id: "loss", title: "Loss", minWidth: 52, alignment: .trailing,
                value: { .number($0.lossPercent) },
                cell: { hop in
                    AnyView(
                        Text(String(format: "%.0f%%", hop.lossPercent))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(hop.lossPercent > 0 ? .orange : .secondary))
                }),
            AppTableColumn(
                id: "sent", title: "Sent", minWidth: 44, alignment: .trailing,
                value: { .number(Double($0.sent)) },
                cell: { hop in
                    AnyView(
                        Text("\(hop.sent)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "last", title: "Last", minWidth: 72, alignment: .trailing,
                value: { .number($0.lastMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(hop.lastMilliseconds))
                            .font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "average", title: "Avg", minWidth: 72, alignment: .trailing,
                value: { .number($0.averageMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(hop.averageMilliseconds))
                            .font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "best", title: "Best", minWidth: 72, alignment: .trailing,
                value: { .number($0.bestMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(hop.bestMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "worst", title: "Worst", minWidth: 72, alignment: .trailing,
                value: { .number($0.worstMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(hop.worstMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "jitter", title: "Jitter", minWidth: 72, alignment: .trailing,
                value: { .number($0.jitterMilliseconds) },
                cell: { hop in
                    AnyView(
                        Text(ToolkitFormat.milliseconds(hop.jitterMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
        ]
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

/// Hand-drawn hop chart: average latency per hop as a line, packet loss per hop
/// as bars on the same x axis. Swift Charts collapsed to an empty card here, so
/// the plot is a plain Canvas with its own axes and it always draws when there
/// is at least one hop.
private struct MTRHopChart: View {
    let hops: [MTRHop]

    private var latencyMax: Double {
        let peak = hops.compactMap(\.averageMilliseconds).max() ?? 0
        return max(10, (peak / 10).rounded(.up) * 10)
    }

    var body: some View {
        Canvas { context, size in
            let leading: CGFloat = 38
            let trailing: CGFloat = 10
            let top: CGFloat = 8
            let bottom: CGFloat = 20
            let plot = CGRect(
                x: leading, y: top,
                width: max(1, size.width - leading - trailing),
                height: max(1, size.height - top - bottom))

            // Latency grid: three lines with ms labels on the left, drawn from
            // the shared chart style so this graph matches every other chart.
            for step in 0...2 {
                let fraction = CGFloat(step) / 2
                let y = plot.maxY - plot.height * fraction
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(line, with: .color(ChartStyle.gridColor), style: ChartStyle.gridStroke)
                let value = Int(latencyMax * Double(step) / 2)
                context.draw(
                    Text("\(value)")
                        .font(ChartStyle.axisLabelFont)
                        .foregroundColor(ChartStyle.axisLabelColor),
                    at: CGPoint(x: leading - 12, y: y), anchor: .trailing)
            }

            guard !hops.isEmpty else { return }
            let stepX = hops.count > 1 ? plot.width / CGFloat(hops.count - 1) : 0
            func x(_ index: Int) -> CGFloat {
                hops.count > 1 ? plot.minX + CGFloat(index) * stepX : plot.midX
            }

            // Loss bars grow from the bottom; 100 % loss fills a third of the plot.
            for (index, hop) in hops.enumerated() where hop.lossPercent > 0 {
                let height = plot.height * 0.33 * CGFloat(min(hop.lossPercent, 100) / 100)
                let bar = CGRect(
                    x: x(index) - 2, y: plot.maxY - height, width: 4, height: max(1, height))
                context.fill(Path(bar), with: .color(AppPalette.warning.opacity(0.55)))
            }

            // Average latency line with a dot per replied hop.
            var path = Path()
            var started = false
            var dots: [CGPoint] = []
            for (index, hop) in hops.enumerated() {
                guard let milliseconds = hop.averageMilliseconds else { continue }
                let point = CGPoint(
                    x: x(index),
                    y: plot.maxY - plot.height * CGFloat(min(milliseconds, latencyMax) / latencyMax))
                if started {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
                dots.append(point)
            }
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5))
            // A route with one replying hop used to draw nothing at all: a path
            // that only moves is not stroked, and a single small dot read as an
            // empty chart. A dashed guide and a ringed marker make the value
            // visible even then.
            if let only = dots.first, dots.count == 1 {
                var guide = Path()
                guide.move(to: CGPoint(x: plot.minX, y: only.y))
                guide.addLine(to: CGPoint(x: plot.maxX, y: only.y))
                context.stroke(
                    guide, with: .color(.accentColor.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            for point in dots {
                let marker = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: marker), with: .color(.accentColor))
                context.stroke(Path(ellipseIn: marker), with: .color(.white.opacity(0.8)), lineWidth: 1)
            }
            if let last = dots.last, let value = hops.compactMap(\.averageMilliseconds).last {
                context.draw(
                    Text(String(format: "%.1f ms", value))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.primary),
                    at: CGPoint(x: min(last.x + 8, plot.maxX - 24), y: max(plot.minY + 6, last.y - 10)),
                    anchor: .leading)
            }

            // Hop numbers along the bottom, thinned out on long routes.
            let stride = max(1, hops.count / 8)
            for (index, hop) in hops.enumerated() where index % stride == 0 {
                context.draw(
                    Text("\(hop.hop)")
                        .font(ChartStyle.axisLabelFont)
                        .foregroundColor(ChartStyle.axisLabelColor),
                    at: CGPoint(x: x(index), y: plot.maxY + 9))
            }
        }
        .frame(height: 170)
        .accessibilityLabel("Average latency and packet loss per hop")
    }
}
