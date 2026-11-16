import LanFiCore
import SwiftUI

/// Compact menu-bar sparkline: no axes, no labels, just the last samples.
struct MenuBarSparkline: View {
    let values: [Double]
    var tint: Color = .primary

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }

            let peak = max(values.max() ?? 0, 1)
            func point(index: Int, value: Double) -> CGPoint {
                let x =
                    values.count > 1
                    ? CGFloat(index) / CGFloat(values.count - 1) * size.width
                    : size.width
                let normalized = min(1, max(0, value / peak))
                return CGPoint(x: x, y: size.height - 1 - CGFloat(normalized) * (size.height - 2))
            }

            guard let first = values.first else {
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: size.height - 1))
                baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(
                    baseline, with: .color(tint.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round))
                return
            }

            var line = Path()
            line.move(to: point(index: 0, value: first))
            for index in values.indices.dropFirst() {
                line.addLine(to: point(index: index, value: values[index]))
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(tint.opacity(0.18)))
            context.stroke(
                line, with: .color(tint),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
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

    @AppStorage("LanFi.menuBar.style") private var styleRaw = AppSettings.MenuBarMeterSettings.LabelStyle.iconAndGraph
        .rawValue
    @AppStorage("LanFi.menuBar.metric") private var metricRaw = AppSettings.MenuBarMeterSettings.Metric.throughput
        .rawValue
    @AppStorage("LanFi.menuBar.unit") private var unitRaw = AppSettings.MenuBarMeterSettings.Unit.bits.rawValue
    @AppStorage("LanFi.signalUnit") private var signalUnitRaw = SignalDisplayMode.dbm.rawValue

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
            guard let latency = diagnostics.publicLatencyMilliseconds else { return "—" }
            return "\\(latency)"
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
            return "Latency " + metricText
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: uptime.downCount > 0 ? "exclamationmark.triangle" : "wifi")
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
        .accessibilityLabel(accessibilityText)
    }
}
