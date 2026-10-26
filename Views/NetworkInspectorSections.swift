import Charts
import SwiftUI

struct IssuesInspectorSection: View {
    let network: NetworkModel
    let metrics: NetworkMetrics?

    private var issues: [NetworkIssue] {
        (metrics?.issues ?? []).sorted { $0.severity > $1.severity }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 7) {
                if issues.isEmpty {
                    Label("No issues detected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: icon(issue.severity))
                                .foregroundColor(color(issue.severity))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.title)
                                    .font(.caption.bold())
                                Text(TechnicalLocalizer.localize(issue.detail))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(4)
        } label: {
            HStack {
                Label("Issues", systemImage: "exclamationmark.triangle")
                Spacer()
                Text("\(issues.count)").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func icon(_ severity: IssueSeverity) -> String {
        switch severity {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

struct HistoryInspectorSection: View {
    let network: NetworkModel
    @ObservedObject var viewModel: AnalyzerViewModel

    private struct Point: Identifiable {
        let id: Int
        let value: Int
        let series: String
    }

    private var points: [Point] {
        let signal = viewModel.signalHistory[network.id] ?? []
        let noise = viewModel.noiseHistory[network.id] ?? []
        let snr = viewModel.snrHistory[network.id] ?? []
        var result: [Point] = []
        for (index, value) in signal.enumerated() {
            result.append(Point(id: index * 3, value: value, series: "Signal"))
        }
        for (index, value) in noise.enumerated() {
            if let value { result.append(Point(id: index * 3 + 1, value: value, series: "Noise")) }
        }
        for (index, value) in snr.enumerated() {
            if let value { result.append(Point(id: index * 3 + 2, value: value, series: "SNR")) }
        }
        return result
    }

    var body: some View {
        GroupBox {
            if points.isEmpty {
                Text("Collecting samples…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Sample", point.id / 3),
                        y: .value("dB", point.value)
                    )
                    .foregroundStyle(by: .value("Metric", point.series))
                    .interpolationMethod(.stepEnd)
                }
                .chartYScale(domain: -105...5)
                .chartXAxis(.hidden)
                .frame(height: 120)
                .accessibilityLabel("Signal, noise and SNR history")
                .accessibilityValue(
                    points.suffix(6).map { "\($0.series) \($0.value) dB" }.joined(separator: ", ")
                )
            }
        } label: {
            Label("Signal / noise / SNR", systemImage: "chart.xyaxis.line")
        }
    }
}

struct UtilizationInspectorSection: View {
    let network: NetworkModel
    @ObservedObject var viewModel: AnalyzerViewModel

    private var values: [Int] {
        (viewModel.utilizationHistory[network.id] ?? []).compactMap { $0 }
    }

    var body: some View {
        GroupBox {
            if values.isEmpty {
                Text("AP does not advertise channel utilization (BSS Load).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                Chart(Array(values.enumerated()), id: \.offset) { item in
                    AreaMark(
                        x: .value("Sample", item.offset),
                        y: .value("Utilization %", item.element)
                    )
                    .foregroundStyle(Color.orange.opacity(0.25))
                    LineMark(
                        x: .value("Sample", item.offset),
                        y: .value("Utilization %", item.element)
                    )
                    .foregroundStyle(.orange)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .frame(height: 100)
                .accessibilityLabel("Channel utilization history")
                .accessibilityValue("Latest \(values.last ?? 0) percent, maximum \(values.max() ?? 0) percent")
            }
        } label: {
            HStack {
                Label("Channel utilization", systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                if let last = values.last {
                    Text("\(last)%").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }
}
