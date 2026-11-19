import SwiftUI

private enum SpeedTestTab: String, CaseIterable, Identifiable {
    case result, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .result: return String(localized: "Result")
        case .history: return String(localized: "History")
        }
    }
}

struct SpeedTestToolView: View {
    @ObservedObject var model: SpeedTestToolModel
    @State private var tab: SpeedTestTab = .result
    @State private var historyNetworkKey: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                Picker("Mode", selection: $tab) {
                    ForEach(SpeedTestTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                switch tab {
                case .result:
                    if let report = model.report {
                        metrics(report)
                        gradeCard(report)
                    } else if !model.isRunning {
                        ToolkitEmptyState(
                            icon: "speedometer",
                            title: "Measure the line",
                            message:
                                "Download, upload, latency and responsiveness from Apple's networkQuality. It uses real test traffic for up to 20 seconds."
                        )
                    }
                case .history:
                    historySection
                }
            }
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                Text("Apple networkQuality")
                    .font(.callout.weight(.medium))
                Text("No third-party service; results stay on this Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("Schedule", selection: $model.schedule) {
                    ForEach(SpeedTestSchedule.allCases) { schedule in
                        Text(schedule.title).tag(schedule)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                Text(nextRunText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if model.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                AppButton("Run Test", tone: .primary) { model.run() }
                    .disabled(model.isRunning)
                AppButton("Clear", tone: .quiet) { model.clear() }
                    .disabled(model.report == nil)
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Testing…") }
        guard let report = model.report else { return String(localized: "Ready") }
        return report.summary
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        return model.report == nil ? .neutral : .good
    }

    private func metrics(_ report: ThroughputReport) -> some View {
        ToolkitCard {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 16)],
                alignment: .leading,
                spacing: 12
            ) {
                ToolkitMetric(
                    title: "Download",
                    value: report.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                ToolkitMetric(
                    title: "Upload",
                    value: report.uploadMbps.map { String(format: "%.0f Mbps", $0) } ?? "—")
                ToolkitMetric(
                    title: "Idle latency",
                    value: report.latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—")
                ToolkitMetric(
                    title: "Responsiveness",
                    value: report.responsiveness.map { String(format: "%.0f RPM", $0) } ?? "—")
            }
        }
    }

    private func gradeCard(_ report: ThroughputReport) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 16) {
                Text(report.bufferbloatGrade ?? "—")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(gradeColor(report.bufferbloatGrade))
                    .frame(width: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        String(
                            format: String(localized: "Bufferbloat %@"),
                            report.bufferbloatLabel ?? "—")
                    )
                    .font(.headline)
                    Text(
                        "Responsiveness measures round trips per minute while the line is saturated. A low grade means latency spikes when something is downloading."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                Text(report.testedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var nextRunText: String {
        guard model.schedule != .off else { return String(localized: "Schedule off") }
        guard let nextRun = model.nextRun else {
            return String(localized: "Runs at the next check")
        }
        return nextRun.formatted(date: .abbreviated, time: .shortened)
    }

    private var historyGroups: [SpeedTestNetworkHistory] {
        model.networkGroups
    }

    private var visibleHistory: [ThroughputMeasurement] {
        model.measurements(forNetwork: historyNetworkKey)
    }

    private var selectedGroup: SpeedTestNetworkHistory? {
        guard let historyNetworkKey else { return nil }
        return historyGroups.first { $0.id == historyNetworkKey }
    }

    private var historySection: some View {
        VStack(spacing: DesignToken.Spacing.medium) {
            if !historyGroups.isEmpty {
                networkPicker
            }
            if let selectedGroup {
                networkSummary(selectedGroup)
            }
            historyCard
        }
    }

    private var networkPicker: some View {
        AppCard(padding: DesignToken.Spacing.medium) {
            HStack(spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Network")
                Picker("Network", selection: $historyNetworkKey) {
                    Text("All networks").tag(String?.none)
                    ForEach(historyGroups) { group in
                        Text("\(group.network.displayName) (\(group.testCount))")
                            .tag(Optional(group.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
                Spacer()
                Text("Speed tests are grouped by the SSID that was connected when they ran.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func networkSummary(_ group: SpeedTestNetworkHistory) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    Image(systemName: "wifi")
                        .foregroundColor(AppPalette.band(.band5))
                    Text(group.network.displayName)
                        .font(.headline)
                    if let bssid = group.network.bssid {
                        Text(bssid)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(String(format: String(localized: "%lld tests"), group.testCount))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let grade = group.latest?.bufferbloatGrade {
                        StatusPill(text: "Bufferbloat \(grade)", tone: gradeTone(grade))
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                    alignment: .leading,
                    spacing: DesignToken.Spacing.medium
                ) {
                    summaryMetric(
                        title: "Latest down",
                        value: group.latest?.report.downloadMbps,
                        unit: "Mbps",
                        delta: group.downloadDeltaMbps,
                        higherIsBetter: true)
                    summaryMetric(
                        title: "Latest up",
                        value: group.latest?.report.uploadMbps,
                        unit: "Mbps",
                        delta: group.uploadDeltaMbps,
                        higherIsBetter: true)
                    summaryMetric(
                        title: "Latency",
                        value: group.latest?.report.latencyMilliseconds,
                        unit: "ms",
                        delta: group.latencyDeltaMilliseconds,
                        higherIsBetter: false)
                    ToolkitMetric(
                        title: "Average down",
                        value: group.averageDownloadMbps.map {
                            String(format: "%.0f Mbps", $0)
                        } ?? "—")
                }
                if let delta = group.downloadDeltaMbps {
                    Text(
                        String(
                            format: String(
                                localized:
                                    "Compared with the previous test on this network: %+.0f Mbps down."
                            ),
                            delta)
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func summaryMetric(
        title: LocalizedStringKey, value: Double?, unit: String, delta: Double?,
        higherIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
            Text(value.map { String(format: "%.0f %@", $0, unit) } ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: DesignToken.Spacing.tight) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let delta, abs(delta) >= 0.5 {
                    Text(String(format: "%+.0f", delta))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundColor(
                            deltaIsGood(delta, higherIsBetter: higherIsBetter)
                                ? AppPalette.ok : AppPalette.danger)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func deltaIsGood(_ delta: Double, higherIsBetter: Bool) -> Bool {
        higherIsBetter ? delta > 0 : delta < 0
    }

    private func gradeTone(_ grade: String) -> StatusTone {
        switch grade {
        case "A", "B": return .good
        case "C": return .warning
        default: return .bad
        }
    }

    private var historyCard: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "History")
                    Spacer()
                    AppButton("Clear", tone: .quiet) { model.clearHistory() }
                        .font(.caption2)
                        .disabled(model.history.isEmpty)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                if visibleHistory.isEmpty {
                    Text(
                        historyNetworkKey == nil
                            ? "Scheduled and manual tests land here."
                            : "No tests recorded on this network yet."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, DesignToken.Spacing.card)
                    .padding(.bottom, DesignToken.Spacing.card)
                } else {
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
                                id: "network", title: "Network", minWidth: 120,
                                value: {
                                    .text(
                                        $0.network?.displayName
                                            ?? String(localized: "Not recorded"))
                                }
                            ) { measurement in
                                Text(
                                    measurement.network?.displayName
                                        ?? String(localized: "Not recorded")
                                )
                                .font(.caption2)
                                .lineLimit(1)
                            },
                            AppTableColumn(
                                id: "down", title: "Down", minWidth: 90,
                                value: { .number($0.report.downloadMbps) }
                            ) { measurement in
                                Text(
                                    measurement.report.downloadMbps.map {
                                        String(format: "%.0f Mbps", $0)
                                    } ?? "—"
                                )
                                .font(.caption.monospacedDigit())
                            },
                            AppTableColumn(
                                id: "up", title: "Up", minWidth: 90,
                                value: { .number($0.report.uploadMbps) }
                            ) { measurement in
                                Text(
                                    measurement.report.uploadMbps.map {
                                        String(format: "%.0f Mbps", $0)
                                    } ?? "—"
                                )
                                .font(.caption.monospacedDigit())
                            },
                            AppTableColumn(
                                id: "latency", title: "Latency", minWidth: 80,
                                value: { .number($0.report.latencyMilliseconds) }
                            ) { measurement in
                                Text(
                                    measurement.report.latencyMilliseconds.map {
                                        String(format: "%.0f ms", $0)
                                    } ?? "—"
                                )
                                .font(.caption.monospacedDigit())
                            },
                            AppTableColumn(
                                id: "grade", title: "Grade", minWidth: 60,
                                value: { .text($0.bufferbloatGrade) }
                            ) { measurement in
                                Text(measurement.bufferbloatGrade ?? "—")
                                    .font(.caption.bold())
                            },
                        ],
                        rows: visibleHistory, initialKey: "when", ascending: false
                    )
                    .frame(height: min(CGFloat(visibleHistory.count) * 24 + 46, 240))
                }
            }
        }
    }

    private func gradeColor(_ grade: String?) -> Color {
        switch grade {
        case "A", "B": return .green
        case "C": return .orange
        case "D", "F": return .red
        default: return .secondary
        }
    }
}
