import SwiftUI

struct SpeedTestToolView: View {
    @ObservedObject var model: SpeedTestToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
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
                historySection
            }
            .padding(18)
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
                Button("Run Test") { model.run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.report == nil)
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return "Testing…" }
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
                    Text("Bufferbloat \(report.bufferbloatLabel ?? "—")")
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
        guard model.schedule != .off else { return "Schedule off" }
        guard let nextRun = model.nextRun else { return "Runs at the next check" }
        return nextRun.formatted(date: .abbreviated, time: .shortened)
    }

    private var historySection: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "History")
                    Spacer()
                    Button("Clear") { model.clearHistory() }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                        .disabled(model.history.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if model.history.isEmpty {
                    Text("Scheduled and manual tests land here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                } else {
                    Table(model.newestFirst) {
                        TableColumn("When") { measurement in
                            Text(
                                measurement.testedAt.formatted(
                                    date: .abbreviated, time: .shortened)
                            )
                            .font(.caption2)
                        }
                        TableColumn("Down") { measurement in
                            Text(
                                measurement.report.downloadMbps.map {
                                    String(format: "%.0f Mbps", $0)
                                } ?? "—"
                            )
                            .font(.caption.monospacedDigit())
                        }
                        .width(90)
                        TableColumn("Up") { measurement in
                            Text(
                                measurement.report.uploadMbps.map {
                                    String(format: "%.0f Mbps", $0)
                                } ?? "—"
                            )
                            .font(.caption.monospacedDigit())
                        }
                        .width(90)
                        TableColumn("Latency") { measurement in
                            Text(
                                measurement.report.latencyMilliseconds.map {
                                    String(format: "%.0f ms", $0)
                                } ?? "—"
                            )
                            .font(.caption.monospacedDigit())
                        }
                        .width(80)
                        TableColumn("Grade") { measurement in
                            Text(measurement.bufferbloatGrade ?? "—")
                                .font(.caption.bold())
                        }
                        .width(60)
                    }
                    .frame(height: min(CGFloat(model.history.count) * 24 + 46, 240))
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
