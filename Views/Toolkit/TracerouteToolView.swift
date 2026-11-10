import AppKit
import SwiftUI

struct TracerouteToolView: View {
    @ObservedObject var model: TracerouteToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let report = model.result {
                    summary(report)
                    hopsTable(report)
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "point.3.connected.trianglepath.dotted",
                        title: "Trace a route",
                        message:
                            "Shows every hop the traffic passes through, with the latency of each router. Uses the system traceroute binary."
                    )
                }
            }
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("Host", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
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
                    Button("Trace") { model.run() }
                        .buttonStyle(.borderedProminent)
                }
                Button("Copy") { copy() }
                    .buttonStyle(.bordered)
                    .disabled(model.result == nil)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.result == nil)
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return "Tracing…" }
        guard let report = model.result else { return "Ready" }
        if report.reachedTarget {
            return "Reached target · \(report.hops.count) hops"
        }
        return "No reply at hop \(report.hops.count)"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let report = model.result else { return .neutral }
        return report.reachedTarget ? .good : .warning
    }

    private func summary(_ report: TracerouteReport) -> some View {
        ToolkitCard {
            HStack(spacing: 22) {
                ToolkitMetric(title: "Target", value: report.host)
                ToolkitMetric(title: "Hops", value: "\(report.hops.count)")
                ToolkitMetric(
                    title: "Reached",
                    value: report.reachedTarget ? "Yes" : "No",
                    tint: report.reachedTarget ? .green : .orange)
                ToolkitMetric(
                    title: "Worst hop",
                    value: ToolkitFormat.milliseconds(
                        report.hops.compactMap(\.averageMilliseconds).max()))
            }
        }
    }

    private func hopsTable(_ report: TracerouteReport) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Route")
                    Spacer()
                    Text(report.startedAt.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(report.hops) {
                    TableColumn("Hop") { hop in
                        Text("\(hop.ttl)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(44)
                    TableColumn("Address") { hop in
                        Text(hop.address ?? "*")
                            .font(.caption.monospaced())
                            .foregroundColor(hop.address == nil ? .secondary : .primary)
                    }
                    TableColumn("Name") { hop in
                        Text(hop.hostname ?? "—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    TableColumn("Latency") { hop in
                        Text(ToolkitFormat.milliseconds(hop.averageMilliseconds))
                            .font(.caption.monospacedDigit())
                    }
                    .width(100)
                    TableColumn("Status") { hop in
                        Text(hop.timedOut ? "No reply" : "Reply")
                            .font(.caption)
                            .foregroundColor(hop.timedOut ? .orange : .secondary)
                    }
                    .width(90)
                }
                .frame(height: min(CGFloat(report.hops.count) * 24 + 28, 420))
            }
        }
    }

    private func copy() {
        guard let report = model.result else { return }
        var lines = ["LanFi traceroute \(report.host)", ""]
        for hop in report.hops {
            lines.append(
                "\(hop.ttl)\t\(hop.address ?? "*")\t\(hop.hostname ?? "")\t\(ToolkitFormat.milliseconds(hop.averageMilliseconds))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
