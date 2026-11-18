import AppKit
import SwiftUI

struct TracerouteToolView: View {
    @ObservedObject var model: TracerouteToolModel

    private enum SortKey: String, CaseIterable, Identifiable {
        case hop, address, name, latency, status
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hop: return String(localized: "Hop")
            case .address: return String(localized: "Address")
            case .name: return String(localized: "Name")
            case .latency: return String(localized: "Latency")
            case .status: return String(localized: "Status")
            }
        }
    }

    @State private var sortKey: SortKey = .hop
    @State private var sortAscending = true

    private func sortedHops(_ hops: [TracerouteHop]) -> [TracerouteHop] {
        let ordered = hops.sorted { lhs, rhs in
            switch sortKey {
            case .hop: return lhs.ttl < rhs.ttl
            case .address:
                return (lhs.address ?? "").localizedStandardCompare(rhs.address ?? "")
                    == .orderedAscending
            case .name:
                return (lhs.hostname ?? "").localizedStandardCompare(rhs.hostname ?? "")
                    == .orderedAscending
            case .latency:
                return (lhs.averageMilliseconds ?? .infinity) < (rhs.averageMilliseconds ?? .infinity)
            case .status: return (lhs.timedOut ? 1 : 0) < (rhs.timedOut ? 1 : 0)
            }
        }
        return sortAscending ? ordered : ordered.reversed()
    }

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
            .appContentPadding()
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToolTargetField(text: $model.host, onSubmit: { model.run() })
                    Stepper(value: $model.maxHops, in: 1...64) {
                        Text("Max hops: \(model.maxHops)")
                            .font(.caption)
                    }
                    .fixedSize()
                    Stepper(value: $model.probes, in: 1...3) {
                        Text("Probes: \(model.probes)")
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
                HStack(spacing: 16) {
                    Stepper(value: $model.waitSeconds, in: 1...10) {
                        Text("Timeout: \(model.waitSeconds) s")
                            .font(.caption)
                    }
                    .fixedSize()
                    Toggle("Resolve names", isOn: $model.resolveNames)
                        .font(.caption)
                    Spacer()
                }
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Tracing…") }
        guard let report = model.result else { return String(localized: "Ready") }
        if report.reachedTarget {
            return String(
                format: String(localized: "Reached target · %lld hops"),
                report.hops.count)
        }
        return String(
            format: String(localized: "No reply at hop %lld"), report.hops.count)
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
                    value: report.reachedTarget ? String(localized: "Yes") : String(localized: "No"),
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
                    TableSortControl(
                        options: SortKey.allCases.map { ($0, $0.title) },
                        selection: $sortKey, ascending: $sortAscending)
                    Spacer()
                    Text(report.startedAt.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                Table(sortedHops(report.hops)) {
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
                    .width(AppColumnWidth.compact)
                    TableColumn("Status") { hop in
                        Text(hop.timedOut ? String(localized: "No reply") : String(localized: "Reply"))
                            .font(.caption)
                            .foregroundColor(hop.timedOut ? .orange : .secondary)
                    }
                    .width(AppColumnWidth.compact)
                }
                .frame(
                    height: ToolkitTableHeight.rows(
                        report.hops.count, row: 26, header: 38, minimum: 210,
                        maximum: 440))
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
