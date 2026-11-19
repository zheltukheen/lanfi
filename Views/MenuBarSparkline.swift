import LanFiCore
import SwiftUI

/// Compact menu-bar sparkline: no axes, no labels, just the last samples.
struct MenuBarSparkline: View {
    let values: [Double]
    var tint: Color = .primary

    var body: some View {
        Canvas { context, size in
            let points = SparklineGeometry.points(values: values, in: size)

            guard let first = points.first else {
                guard let (start, end) = SparklineGeometry.baseline(in: size) else { return }
                var baseline = Path()
                baseline.move(to: start)
                baseline.addLine(to: end)
                context.stroke(
                    baseline,
                    with: .color(tint.opacity(ChartStyle.sparklineBaselineOpacity)),
                    style: ChartStyle.sparklineStroke)
                return
            }

            var line = Path()
            line.move(to: first)
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(ChartStyle.sparklineFillOpacity)))
            context.stroke(line, with: .color(tint), style: ChartStyle.sparklineStroke)
        }
        .accessibilityHidden(true)
    }
}

/// The `MenuBarExtra` label: icon plus an optional live number and sparkline.
struct MenuBarLabel: View {
    @ObservedObject var meter: MenuBarMeterModel
    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @ObservedObject var uptime: UptimeMonitor
    @ObservedObject var connectivity: ConnectivityWatchdog

    @AppStorage(AppSettingsKey.menuBarStyle.rawValue) private var styleRaw = AppSettings.MenuBarMeterSettings.LabelStyle
        .iconAndGraph
        .rawValue
    @AppStorage(AppSettingsKey.menuBarMetric.rawValue) private var metricRaw = AppSettings.MenuBarMeterSettings.Metric
        .throughput
        .rawValue
    @AppStorage(AppSettingsKey.menuBarUnit.rawValue) private var unitRaw = AppSettings.MenuBarMeterSettings.Unit.bits
        .rawValue
    @AppStorage(AppSettingsKey.signalUnit.rawValue) private var signalUnitRaw = SignalDisplayMode.dbm.rawValue

    private var style: AppSettings.MenuBarMeterSettings.LabelStyle {
        AppSettings.MenuBarMeterSettings.LabelStyle(rawValue: styleRaw) ?? .iconAndGraph
    }

    private var metric: AppSettings.MenuBarMeterSettings.Metric {
        AppSettings.MenuBarMeterSettings.Metric(rawValue: metricRaw) ?? .throughput
    }

    private var unit: ThroughputFormatter.Unit {
        AppSettings.MenuBarMeterSettings.Unit(rawValue: unitRaw) == .bytes ? .bytes : .bits
    }

    private var showsGraph: Bool { style.showsGraph && metric == .throughput }

    private var showsNumber: Bool {
        style.showsNumber || (style.showsGraph && metric != .throughput)
    }

    private var signalMode: SignalDisplayMode {
        SignalDisplayMode(rawValue: signalUnitRaw) ?? .dbm
    }

    private var connected: NetworkModel? {
        guard let bssid = viewModel.currentConnectedBSSID else { return nil }
        return viewModel.networks.first { $0.bssid == bssid }
    }

    private var metricText: String {
        switch metric {
        case .throughput:
            return ThroughputFormatter.compact(meter.primaryRate?.totalBytesPerSecond ?? 0, unit: unit)
        case .signal:
            guard let connected else { return "—" }
            return NetworkColumnFormatter.formatSignal(connected.signal, mode: signalMode)
        case .quality:
            guard let connected, let metrics = viewModel.metrics(for: connected) else { return "—" }
            return "\\(metrics.qualityScore)"
        case .latency:
            // The watchdog samples every few seconds, so the label reflects the
            // link now instead of the last manual diagnostics run.
            let latency =
                connectivity.latencyMilliseconds ?? diagnostics.publicLatencyMilliseconds
            guard let latency else { return "—" }
            return "\\(latency)"
        }
    }

    /// The menu-bar icon follows the watchdog verdict, so a dead WAN looks
    /// different from a healthy Wi-Fi link.
    private var statusSymbol: String {
        switch connectivity.verdict {
        case .offline: return "wifi.slash"
        case .captivePortal: return "lock.fill"
        case .online, .unknown:
            return uptime.downCount > 0 ? "exclamationmark.triangle" : "wifi"
        }
    }

    private var accessibilityText: String {
        switch metric {
        case .throughput:
            return "Throughput " + ThroughputFormatter.rate(meter.primaryRate?.totalBytesPerSecond ?? 0, unit: unit)
        case .signal:
            return "Signal " + metricText
        case .quality:
            return "Quality " + metricText
        case .latency:
            let verdict = connectivity.verdict
            let state = verdict == .unknown ? "" : ", \(verdict.title)"
            return "Latency " + metricText + state
        }
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Image(systemName: statusSymbol)
                .symbolRenderingMode(.monochrome)
            if showsGraph {
                MenuBarSparkline(values: meter.samples, tint: .primary)
                    .frame(width: 34, height: 12)
            }
            if showsNumber {
                Text(verbatim: metricText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(showsGraph ? "Sparkline shown" : "")
    }
}
