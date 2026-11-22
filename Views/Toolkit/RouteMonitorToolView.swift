import SwiftUI
import LanFiCore

/// P3.2 — continuous route monitor: pick one destination, keep a rolling window
/// of rounds and read per-hop latency and loss as a heatmap.
struct RouteMonitorToolView: View {
    @ObservedObject var monitor: RouteMonitor
    @ObservedObject private var analysisTarget = AnalysisTarget.shared
    @State private var host = ""
    @State private var didPrimeTarget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                controls
                if let error = monitor.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if monitor.samples.isEmpty {
                    emptyOrMeasuring
                } else {
                    summary
                    heatmapCard
                }
                settingsCard
                eventsCard
            }
            .appContentPadding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            monitor.setPanelVisible(true)
            primeTarget()
        }
        .onDisappear { monitor.setPanelVisible(false) }
    }

    // MARK: - Controls

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolTargetField(text: $host, maxWidth: 240, onSubmit: { start() })
                    if monitor.isRunning {
                        AppButton("Stop", tone: .secondary) { monitor.stop() }
                    } else {
                        AppButton("Start", tone: .primary) { start() }
                    }
                    AppButton("Clear", tone: .quiet) { monitor.clear() }
                        .disabled(monitor.samples.isEmpty && monitor.routeChanges.isEmpty)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                    Spacer()
                }
                Text(
                    "One traceroute round every 10 s while this screen is open, every 30 s while it is closed, and every 60 s in the background."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var emptyOrMeasuring: some View {
        if monitor.isRunning {
            ToolkitCard {
                HStack(spacing: DesignToken.Spacing.medium) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Measuring the route…")
                            .font(.caption.weight(.semibold))
                        Text("The heatmap appears after the first round.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            ToolkitEmptyState(
                icon: "square.grid.3x3.middle.filled",
                title: "Measure a route continuously",
                message:
                    "Every hop's latency and loss on one scrolling grid, so a flapping router or an evening congestion pattern is visible instead of remembered."
            )
        }
    }

    private var statusText: String {
        if monitor.isRunning {
            return String(format: String(localized: "Monitoring %@"), monitor.target)
        }
        if let at = monitor.lastSampleAt {
            return String(
                format: String(localized: "Last %lld samples"), monitor.samples.count)
                + " · " + at.formatted(date: .omitted, time: .shortened)
        }
        return String(localized: "Not monitoring")
    }

    private var statusTone: ToolkitTone {
        if monitor.isRunning { return .running }
        return monitor.samples.isEmpty ? .neutral : .good
    }

    // MARK: - Summary

    private var summary: some View {
        let stats = RouteHopStatistics.compute(samples: monitor.samples)
        let latest = monitor.samples.last
        let worstLoss = stats.map(\.lossPercent).max() ?? 0
        return ToolkitCard {
            HStack(spacing: DesignToken.Spacing.large) {
                ToolkitMetric(title: "Target", value: monitor.target)
                ToolkitMetric(title: "Samples", value: "\(monitor.samples.count)/\(RouteMonitor.windowCapacity)")
                ToolkitMetric(title: "Hops", value: "\(stats.count)")
                ToolkitMetric(
                    title: "Latest latency",
                    value: ToolkitFormat.milliseconds(latest?.destinationLatencyMilliseconds))
                ToolkitMetric(
                    title: "Loss over window",
                    value: String(format: "%.0f%%", worstLoss),
                    tint: worstLoss >= monitor.settings.lossThresholdPercent
                        ? AppPalette.warning : .primary)
            }
        }
    }

    // MARK: - Heatmap

    private var heatmapCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Per-hop heatmap")
                    Spacer()
                    legend(color: AppPalette.ok, text: "Fast")
                    legend(color: AppPalette.warning, text: "Slow")
                    legend(color: AppPalette.danger, text: "No reply")
                }
                RouteHeatmapChart(samples: monitor.samples, settings: monitor.settings)
                Text(
                    "Time runs left to right, hops top to bottom. Green is below half the latency threshold, orange is above it, and red is a missed reply."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private func legend(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 8)
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "Route thresholds")
                LabeledContent("Latency threshold") {
                    HStack(spacing: DesignToken.Spacing.small) {
                        Slider(
                            value: latencyBinding, in: 20...500, step: 10
                        )
                        .frame(width: 190)
                        Text("\(Int(monitor.settings.latencyThresholdMilliseconds)) ms")
                            .font(.caption.monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                LabeledContent("Loss threshold") {
                    HStack(spacing: DesignToken.Spacing.small) {
                        Slider(value: lossBinding, in: 5...100, step: 5)
                            .frame(width: 190)
                        Text("\(Int(monitor.settings.lossThresholdPercent))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                Toggle("Notify on route change", isOn: notifyRouteBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Notify when a hop crosses a threshold", isOn: notifyThresholdBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Divider()
                Text("One destination at a time")
                    .font(.caption.weight(.semibold))
                Text(
                    "LanFi keeps one route monitor for the whole app. It slows down while this screen is closed and keeps the same rolling window when you come back."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsCard: some View {
        let changes = monitor.routeChanges
        let crossings = monitor.thresholdCrossings
        if !changes.isEmpty || !crossings.isEmpty {
            ToolkitCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Route events")
                    ForEach(changes) { change in
                        eventRow(
                            icon: "arrow.triangle.branch",
                            title: String(localized: "Route changed"),
                            detail: change.summary, at: change.at)
                    }
                    ForEach(crossings) { crossing in
                        eventRow(
                            icon: crossing.kind == .latency
                                ? "clock.badge.exclamationmark" : "arrow.down.right.circle",
                            title: String(localized: "Threshold crossing"),
                            detail: crossing.summary, at: nil)
                    }
                }
            }
        }
    }

    private func eventRow(
        icon: String, title: String, detail: String, at date: Date?
    ) -> some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
            Image(systemName: icon)
                .foregroundColor(AppPalette.warning)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let date {
                Text(date.formatted(date: .omitted, time: .standard))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Actions and bindings

    private func primeTarget() {
        guard !didPrimeTarget else { return }
        didPrimeTarget = true
        guard host.isEmpty else { return }
        if !monitor.target.isEmpty {
            host = monitor.target
        } else if !analysisTarget.value.isEmpty {
            host = analysisTarget.value
        } else {
            host = RouteMonitor.fallbackTarget
        }
    }

    private func start() {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        analysisTarget.remember(value)
        if monitor.settings.notifyOnRouteChange || monitor.settings.notifyOnThreshold {
            Task { _ = await MonitorNotifier.shared.requestAuthorization() }
        }
        monitor.start(host: value)
    }

    private var latencyBinding: Binding<Double> {
        Binding(
            get: { monitor.settings.latencyThresholdMilliseconds },
            set: { monitor.settings.latencyThresholdMilliseconds = $0 })
    }

    private var lossBinding: Binding<Double> {
        Binding(
            get: { monitor.settings.lossThresholdPercent },
            set: { monitor.settings.lossThresholdPercent = $0 })
    }

    private var notifyRouteBinding: Binding<Bool> {
        Binding(
            get: { monitor.settings.notifyOnRouteChange },
            set: { monitor.settings.notifyOnRouteChange = $0 })
    }

    private var notifyThresholdBinding: Binding<Bool> {
        Binding(
            get: { monitor.settings.notifyOnThreshold },
            set: { monitor.settings.notifyOnThreshold = $0 })
    }
}

/// Scrolling per-hop grid: one column per sample, one row per hop. A cell is
/// the round's latency colour or the loss colour when the hop did not answer.
private struct RouteHeatmapChart: View {
    let samples: [RouteSample]
    let settings: RouteMonitorSettings

    private var hopNumbers: [Int] {
        Array(Set(samples.flatMap { $0.hops.map(\.hop) })).sorted()
    }

    var body: some View {
        Canvas { context, size in
            let leading: CGFloat = 26
            let trailing: CGFloat = 4
            let top: CGFloat = 4
            let bottom: CGFloat = 18
            let plot = CGRect(
                x: leading, y: top,
                width: max(1, size.width - leading - trailing),
                height: max(1, size.height - top - bottom))

            let hops = hopNumbers
            guard !hops.isEmpty, !samples.isEmpty else { return }

            let columnWidth = plot.width / CGFloat(samples.count)
            let rowHeight = plot.height / CGFloat(hops.count)

            for (column, sample) in samples.enumerated() {
                for (row, hop) in hops.enumerated() {
                    guard let value = sample.hop(hop) else { continue }
                    let rect = CGRect(
                        x: plot.minX + CGFloat(column) * columnWidth,
                        y: plot.minY + CGFloat(row) * rowHeight,
                        width: max(1, columnWidth - 0.5),
                        height: max(1, rowHeight - 0.5))
                    let color =
                        value.didReply
                        ? latencyColor(value.latencyMilliseconds ?? 0)
                        : AppPalette.danger.opacity(0.85)
                    context.fill(Path(rect), with: .color(color))
                }
            }

            // Hop numbers on the left, thinned out on long routes.
            let hopStride = max(1, hops.count / 8)
            for (index, hop) in hops.enumerated() where index % hopStride == 0 {
                context.draw(
                    Text("\(hop)")
                        .font(ChartStyle.axisLabelFont)
                        .foregroundColor(ChartStyle.axisLabelColor),
                    at: CGPoint(
                        x: plot.minX - 6,
                        y: plot.minY + (CGFloat(index) + 0.5) * rowHeight),
                    anchor: .trailing)
            }

            // First and last sample time along the bottom.
            if let first = samples.first?.at, let last = samples.last?.at {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                context.draw(
                    Text(formatter.string(from: first))
                        .font(ChartStyle.axisLabelFont)
                        .foregroundColor(ChartStyle.axisLabelColor),
                    at: CGPoint(x: plot.minX, y: plot.maxY + 9), anchor: .leading)
                if samples.count > 1 {
                    context.draw(
                        Text(formatter.string(from: last))
                            .font(ChartStyle.axisLabelFont)
                            .foregroundColor(ChartStyle.axisLabelColor),
                        at: CGPoint(x: plot.maxX, y: plot.maxY + 9), anchor: .trailing)
                }
            }
        }
        .frame(height: 220)
        .accessibilityLabel("Per-hop latency and loss over time")
    }

    private func latencyColor(_ latency: Double) -> Color {
        let threshold = max(1, settings.latencyThresholdMilliseconds)
        switch latency {
        case ..<(threshold * 0.5):
            return AppPalette.ok.opacity(0.75)
        case ..<threshold:
            return AppPalette.warning.opacity(0.65)
        case ..<(threshold * 2):
            return AppPalette.warning.opacity(0.9)
        default:
            return AppPalette.danger.opacity(0.85)
        }
    }
}
