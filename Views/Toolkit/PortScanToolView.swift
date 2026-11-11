import AppKit
import SwiftUI

struct PortScanToolView: View {
    @ObservedObject var model: PortScanToolModel

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
            .padding(18)
        }
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Host", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
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
        if model.isRunning { return String(localized: "Scanning…") }
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
            HStack(spacing: 20) {
                ToolkitMetric(title: "Open", value: "\(model.openCount)", tint: .green)
                ToolkitMetric(title: "Closed", value: "\(model.closedCount)", tint: .red)
                ToolkitMetric(title: "Filtered", value: "\(model.filteredCount)", tint: .orange)
                ToolkitMetric(title: "Scanned", value: "\(model.results.count)")
                ToolkitMetric(title: "Host", value: model.host)
            }
        }
    }

    private var resultsTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Ports")
                    Spacer()
                    Text(model.portSpec)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(model.results) {
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
                    .width(90)
                    TableColumn("Detail") { result in
                        Text(result.detail ?? "")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(height: min(CGFloat(model.results.count) * 26 + 40, 560))
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
                    Spacer()
                    Text("Best-effort: no response = open|filtered")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)
                Table(model.udpResults) {
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
                .frame(height: min(CGFloat(model.udpResults.count) * 26 + 40, 300))
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
