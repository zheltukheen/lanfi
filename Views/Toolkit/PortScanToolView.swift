import AppKit
import SwiftUI

struct PortScanToolView: View {
    @ObservedObject var model: PortScanToolModel

    private enum SortKey: String, CaseIterable, Identifiable {
        case port, service, state, response, detail
        var id: String { rawValue }
        var title: String {
            switch self {
            case .port: return String(localized: "Port")
            case .service: return String(localized: "Service")
            case .state: return String(localized: "State")
            case .response: return String(localized: "Response")
            case .detail: return String(localized: "Detail")
            }
        }
    }

    @State private var tcpSortKey: SortKey = .port
    @State private var tcpAscending = true
    @State private var udpSortKey: SortKey = .port
    @State private var udpAscending = true

    private func sorted(
        _ rows: [PortScanResult], key: SortKey, ascending: Bool
    ) -> [PortScanResult] {
        let ordered = rows.sorted { lhs, rhs in
            switch key {
            case .port: return lhs.port < rhs.port
            case .service:
                return (lhs.service ?? "").localizedStandardCompare(rhs.service ?? "")
                    == .orderedAscending
            case .state:
                return lhs.state.label.localizedStandardCompare(rhs.state.label)
                    == .orderedAscending
            case .response:
                return (lhs.responseMilliseconds ?? .infinity)
                    < (rhs.responseMilliseconds ?? .infinity)
            case .detail:
                return (lhs.detail ?? "").localizedStandardCompare(rhs.detail ?? "")
                    == .orderedAscending
            }
        }
        return ascending ? ordered : ordered.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if !model.results.isEmpty {
                    summary
                    HStack(alignment: .top, spacing: 14) {
                        resultsTable
                        inspector
                            .frame(width: 230)
                    }
                    if !model.udpResults.isEmpty {
                        udpTable
                    }
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "square.grid.3x3",
                        title: "Check open ports",
                        message:
                            "TCP connect scan with a bounded number of concurrent probes. Open, closed and filtered states are reported separately."
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
                    ToolTargetField(
                        text: $model.host, maxWidth: 190, onSubmit: { model.run() })
                    TextField("21-23,80,443", text: $model.portSpec)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220, maxWidth: 380)
                        .layoutPriority(1)
                    Menu("Presets") {
                        ForEach(PortPreset.allCases) { preset in
                            Button(preset.title) { model.applyPreset(preset) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    if model.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Scan") { model.run() }
                            .buttonStyle(.borderedProminent)
                    }
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                if model.isRunning, model.totalPorts > 0 {
                    ProgressView(
                        value: Double(model.results.count),
                        total: Double(max(model.totalPorts, 1))
                    )
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                }
                HStack(spacing: 14) {
                    Stepper(value: $model.timeout, in: 0.5...10, step: 0.5) {
                        Text(
                            String(
                                format: String(localized: "Timeout: %.1f s"), model.timeout)
                        )
                        .font(.caption)
                    }
                    .fixedSize()
                    Stepper(value: $model.concurrency, in: 1...64) {
                        Text(
                            String(
                                format: String(localized: "Concurrent: %lld"),
                                model.concurrency)
                        )
                        .font(.caption)
                    }
                    .fixedSize()
                    Toggle("Detect service versions", isOn: $model.detectServices)
                        .font(.caption)
                    Toggle("Also UDP (10 ports)", isOn: $model.includeUDP)
                        .font(.caption)
                    Spacer()
                    Button("Copy") { copy() }
                        .buttonStyle(.bordered)
                        .disabled(model.results.isEmpty)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.results.isEmpty)
                }
                Text(
                    model.includeUDP
                        ? String(localized: "TCP + UDP probes · no administrator rights")
                        : String(localized: "TCP connect only · no administrator rights")
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private var statusText: String {
        if model.isRunning {
            if model.totalPorts > 0 {
                return String(
                    format: String(localized: "Scanning %lld/%lld"),
                    model.results.count, model.totalPorts)
            }
            return String(localized: "Scanning…")
        }
        guard !model.results.isEmpty else { return String(localized: "Ready") }
        return String(
            format: String(localized: "%lld/%lld open"), model.openCount,
            max(model.results.count, 1))
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard !model.results.isEmpty else { return .neutral }
        return model.openCount > 0 ? .good : .warning
    }

    private var summary: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 20) {
                    ToolkitMetric(title: "Open", value: "\(model.openCount)", tint: .green)
                    ToolkitMetric(title: "Closed", value: "\(model.closedCount)", tint: .red)
                    ToolkitMetric(title: "Filtered", value: "\(model.filteredCount)", tint: .orange)
                    ToolkitMetric(title: "Scanned", value: "\(model.results.count)")
                    ToolkitMetric(title: "Host", value: model.host)
                }
                if model.results.count > 5, model.openCount == model.results.count {
                    Label(
                        "Every probed port accepted a connection. A transparent proxy or captive portal may be intercepting traffic.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
            }
        }
    }

    private var resultsTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Ports")
                    TableSortControl(
                        options: SortKey.allCases.map { ($0, $0.title) },
                        selection: $tcpSortKey, ascending: $tcpAscending)
                    Spacer()
                    Text(model.portSpec)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                Table(sorted(model.results, key: tcpSortKey, ascending: tcpAscending)) {
                    TableColumn("Port") { result in
                        Text("\(result.port)/tcp")
                            .font(.caption.monospacedDigit())
                    }
                    .width(76)
                    TableColumn("Service") { result in
                        Text(result.service ?? "—")
                            .font(.caption)
                    }
                    TableColumn("State") { result in
                        HStack(spacing: 5) {
                            ToolkitStateDot(state: result.state)
                            Text(result.state.label)
                                .font(.caption)
                        }
                    }
                    .width(80)
                    TableColumn("Response") { result in
                        Text(ToolkitFormat.milliseconds(result.responseMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(AppColumnWidth.compact)
                    TableColumn("Detail") { result in
                        Text(result.detail ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(
                    height: ToolkitTableHeight.rows(
                        model.results.count, row: 28, header: 42, minimum: 220,
                        maximum: 560))
            }
        }
    }

    private var inspector: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 9) {
                ToolkitSectionLabel(text: "Open")
                if model.openCount == 0 {
                    Text("No open ports in this scan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.results.filter { $0.state == .open }) { result in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(result.port)/tcp")
                                .font(.caption.monospacedDigit().weight(.semibold))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.service ?? "")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if let detail = result.detail {
                                    Text(detail)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(ToolkitFormat.milliseconds(result.responseMilliseconds))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Divider()
                Text("A closed port answered with a refusal; a filtered port did not answer before the timeout.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(
                    "A transparent proxy can accept every connection; this scan reports the TCP handshake, not the service behind it."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private var udpTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "UDP")
                    TableSortControl(
                        options: SortKey.allCases.map { ($0, $0.title) },
                        selection: $udpSortKey, ascending: $udpAscending)
                    Spacer()
                    Text("Best-effort: no response = open|filtered")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)
                Table(sorted(model.udpResults, key: udpSortKey, ascending: udpAscending)) {
                    TableColumn("Port") { result in
                        Text("\(result.port)/udp")
                            .font(.caption.monospacedDigit())
                    }
                    .width(76)
                    TableColumn("Service") { result in
                        Text(result.service ?? "—")
                            .font(.caption)
                    }
                    TableColumn("State") { result in
                        HStack(spacing: 5) {
                            ToolkitStateDot(state: result.state)
                            Text(result.state.label)
                                .font(.caption)
                        }
                    }
                    .width(80)
                    TableColumn("Detail") { result in
                        Text(result.detail ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(
                    height: ToolkitTableHeight.rows(
                        model.udpResults.count, row: 28, header: 42, minimum: 170,
                        maximum: 320))
            }
        }
    }

    private func copy() {
        var lines = ["LanFi port scan \(model.host)", ""]
        for result in model.results {
            lines.append(
                "\(result.port)/tcp\t\(result.service ?? "-")\t\(result.state.rawValue)\t\(ToolkitFormat.milliseconds(result.responseMilliseconds))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
