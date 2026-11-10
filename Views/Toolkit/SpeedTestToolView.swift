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
        guard let report = model.report else { return "Ready" }
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

    private func gradeColor(_ grade: String?) -> Color {
        switch grade {
        case "A", "B": return .green
        case "C": return .orange
        case "D", "F": return .red
        default: return .secondary
        }
    }
}
