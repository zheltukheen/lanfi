import SwiftUI
import Charts
import Accessibility

// MARK: - Shared quality components

struct QualityScoreView: View {
    let score: Int
    var compact: Bool = false

    private var color: Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .mint
        case 40..<65: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(score)")
                .font(compact ? .caption.bold() : .title3.bold())
                .foregroundColor(color)
                .monospacedDigit()
            if !compact {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * CGFloat(score) / 100))
                    }
                }
                .frame(height: 6)
            }
            Text(QualityGrade(score: score).label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quality score \(score) out of 100, \(QualityGrade(score: score).label)")
    }
}

struct ScoreRow: View {
    let label: String
    let score: Int
    var detail: String? = nil
    var showsValue: Bool = true

    private var color: Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .mint
        case 40..<65: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundColor(.secondary)
                Spacer()
                if let detail {
                    Text(detail).font(.caption2).foregroundColor(.secondary)
                }
                if showsValue {
                    Text("\(score)")
                        .font(.caption.bold())
                        .foregroundColor(color)
                        .monospacedDigit()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * CGFloat(score) / 100))
                }
            }
            .frame(height: 4)
        }
    }
}

struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    var subtitle: String? = nil
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.bold())
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct RecommendationCard: View {
    let recommendation: ChannelRecommendation

    private var tint: Color {
        switch recommendation.score {
        case 85...: return .green
        case 60..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(recommendation.band.label)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Text("Score \(recommendation.score)")
                    .font(.caption2.bold())
                    .foregroundColor(tint)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Ch \(recommendation.channel)")
                    .font(.title2.bold())
                Text("\(recommendation.widthMHz) MHz")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScoreRow(label: "Channel quality", score: recommendation.score, showsValue: false)

            Text(recommendation.rationale)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Label("\(recommendation.overlappingCount) overlap", systemImage: "dot.radiowaves.left.and.right")
                if recommendation.isDFS {
                    Label("DFS", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Insights panel

struct InsightsView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var occupancyBand: WiFiBand = .band24

    private var report: AnalysisReport { viewModel.analysis }

    private var availableBands: [WiFiBand] {
        WiFiBand.allCases.filter { band in
            report.recommendationsByBand[band] != nil
        }
    }

    var body: some View {
        Group {
            if report.analyzedNetworkCount == 0 {
                emptyState
            } else {
                content
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.35))
            Text("Insights appear after the first scan")
                .font(.headline)
            Text("LanFi scores every network, recommends the quietest channels and audits security.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                scopeBanner
                summary
                channelSection
                HStack(alignment: .top, spacing: 14) {
                    securitySection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    occupancySection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(14)
        }
    }

    private var scopeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("All visible networks")
                    .font(.caption.bold())
                Text("These insights cover the whole scan. Use the inspector or Protocols tab for one network.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let connected = viewModel.connectedNetwork {
                Label(connected.displaySSID, systemImage: "wifi")
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Text("No active connection")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(9)
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StatCard(
                title: "Networks",
                value: "\(report.analyzedNetworkCount)",
                subtitle: "\(viewModel.networks.count) visible after filters"
            )
            StatCard(
                title: "Average quality",
                value: "\(report.averageQuality)",
                subtitle: QualityGrade(score: report.averageQuality).label,
                tint: report.averageQuality >= 65 ? .green : .orange
            )
            StatCard(
                title: "Security findings",
                value: "\(report.securityFindings.count)",
                subtitle: "\(report.criticalFindingCount) critical",
                tint: report.criticalFindingCount > 0 ? .red : .green
            )
            StatCard(
                title: "Best 5 GHz",
                value: bestLabel(for: .band5),
                subtitle: "Recommended channel"
            )
        }
    }

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channel Recommendations")
                .font(.headline)
            Text("Weighted by overlapping airtime, signal strength and reported channel utilization.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 10) {
                ForEach(availableBands, id: \.self) { band in
                    if let best = report.bestChannel(for: band) {
                        RecommendationCard(recommendation: best)
                    }
                }
                if availableBands.isEmpty {
                    Text("No channel data available.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Security Audit")
                .font(.headline)

            if report.securityFindings.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                    Text("No security issues detected in this scan.")
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(findingGroups.prefix(5).enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Divider() }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: group.severity))
                                .foregroundColor(color(for: group.severity))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.caption.bold())
                                Text(group.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text("\(group.count)")
                                .font(.caption2.bold())
                                .foregroundColor(color(for: group.severity))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color(for: group.severity).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
            }
        }
    }

    private struct FindingGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let severity: IssueSeverity
        let count: Int
    }

    private var findingGroups: [FindingGroup] {
        let grouped = Dictionary(grouping: report.securityFindings) { "\($0.severity.rawValue)-\($0.title)" }
        return grouped.values.compactMap { findings in
            guard let first = findings.first else { return nil }
            let names = Array(Set(findings.map(\.ssid))).sorted()
            let subtitle: String
            if findings.count == 1 {
                subtitle = "\(first.ssid) — \(first.detail)"
            } else {
                subtitle =
                    "\(names.prefix(3).joined(separator: ", "))\(names.count > 3 ? " + more" : "") — \(first.detail)"
            }
            return FindingGroup(
                id: "\(first.severity.rawValue)-\(first.title)",
                title: first.title,
                subtitle: subtitle,
                severity: first.severity,
                count: findings.count
            )
        }
        .sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.count > $1.count
        }
    }

    private var occupancySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Channel Occupancy")
                    .font(.headline)
                Spacer()
                Picker("Band", selection: $occupancyBand) {
                    ForEach(availableBands, id: \.self) { band in
                        Text(band.label).tag(band)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
                .controlSize(.small)
            }

            let data = report.occupancy.filter { $0.band == occupancyBand }
            if data.isEmpty {
                Text("No networks observed in \(occupancyBand.label).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Channel", item.channel),
                        y: .value("Networks", item.networkCount)
                    )
                    .foregroundStyle(color(for: item.band))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        if item.networkCount > 1 {
                            Text("\(item.networkCount)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisValueLabel {
                            if let channel = value.as(Int.self) {
                                Text("\(channel)").font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let count = value.as(Int.self) {
                                Text("\(count)").font(.caption2)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityChartDescriptor(OccupancyDescriptor(rows: data, band: occupancyBand))
                .accessibilityLabel("Channel occupancy for \(occupancyBand.label)")
                .accessibilityValue(
                    data.map { "channel \($0.channel): \($0.networkCount) networks" }.joined(separator: ", ")
                )
                .frame(height: 150)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func bestLabel(for band: WiFiBand) -> String {
        guard let best = report.bestChannel(for: band) else { return "—" }
        return "Ch \(best.channel)"
    }

    private func color(for band: WiFiBand) -> Color {
        switch band {
        case .band24: return .orange
        case .band5: return .blue
        case .band6: return .purple
        case .unknown: return .gray
        }
    }

    private func color(for severity: IssueSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private func icon(for severity: IssueSeverity) -> String {
        switch severity {
        case .critical: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

private struct OccupancyDescriptor: AXChartDescriptorRepresentable {
    let rows: [ChannelOccupancy]
    let band: WiFiBand

    func makeChartDescriptor() -> AXChartDescriptor {
        let channels = rows.map(\.channel)
        let maxChannel = max(channels.max() ?? 1, 1)
        let minChannel = min(channels.min() ?? 1, maxChannel)
        let maxCount = max(rows.map(\.networkCount).max() ?? 1, 1)
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Channel",
            range: Double(minChannel)...Double(maxChannel),
            gridlinePositions: []
        ) { value in "Channel \(Int(value))" }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Networks",
            range: 0...Double(maxCount),
            gridlinePositions: []
        ) { value in "\(Int(value)) networks" }
        let points = rows.map { row in
            AXDataPoint(
                x: Double(row.channel),
                y: Double(row.networkCount),
                label: "Channel \(row.channel), \(row.networkCount) networks"
            )
        }
        return AXChartDescriptor(
            title: "Channel occupancy",
            summary: "\(band.label), \(rows.count) channels",
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [AXDataSeriesDescriptor(name: band.label, isContinuous: false, dataPoints: points)]
        )
    }
}
