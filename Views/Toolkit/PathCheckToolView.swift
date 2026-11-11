import SwiftUI

struct PathCheckToolView: View {
    @ObservedObject var model: PathCheckToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if !model.results.isEmpty {
                    summary
                    resultsTable
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "Check host and ports",
                        message:
                            "TCP connect probes tell you whether services are reachable from this Mac, without traceroute privileges."
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
                    TextField("example.com", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 230)
                    TextField("80,443", text: $model.portsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
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
                        Button("Check") { model.run() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.results.isEmpty)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                Text("Up to 32 ports per run; each port gets its own TCP handshake.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Connecting…") }
        guard !model.results.isEmpty else { return String(localized: "Ready") }
        return String(
            format: String(localized: "%lld/%lld reachable"),
            model.reachableCount, model.results.count)
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard !model.results.isEmpty else { return .neutral }
        return model.reachableCount > 0 ? .good : .warning
    }

    private var summary: some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(
                    title: "Reachable", value: "\(model.reachableCount)", tint: .green)
                ToolkitMetric(title: "Checked", value: "\(model.results.count)")
                ToolkitMetric(title: "Host", value: model.host)
                Spacer()
            }
        }
    }

    private var resultsTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Ports")
                    Spacer()
                    Text(model.portsText)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
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
                    TableColumn("State") { result in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(stateColor(result))
                                .frame(width: 7, height: 7)
                            Text(stateTitle(result))
                                .font(.caption)
                        }
                    }
                    .width(100)
                    TableColumn("Response") { result in
                        Text(ToolkitFormat.milliseconds(milliseconds(result)))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(95)
                    TableColumn("Detail") { result in
                        Text(detail(result))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(height: min(CGFloat(model.results.count) * 30 + 42, 420))
            }
        }
    }

    private func stateTitle(_ result: PathCheckResult) -> String {
        switch result.outcome {
        case .open: return String(localized: "Reachable")
        case .closed: return String(localized: "Refused")
        case .filtered: return String(localized: "No response")
        }
    }

    private func stateColor(_ result: PathCheckResult) -> Color {
        switch result.outcome {
        case .open: return .green
        case .closed: return .red
        case .filtered: return .orange
        }
    }

    private func milliseconds(_ result: PathCheckResult) -> Double? {
        switch result.outcome {
        case .open(let value): return value
        case .closed(let value, _): return value
        case .filtered: return nil
        }
    }

    private func detail(_ result: PathCheckResult) -> String {
        switch result.outcome {
        case .open:
            return String(localized: "TCP handshake completed.")
        case .closed(_, let detail):
            return detail ?? String(localized: "Host answered, nothing is listening.")
        case .filtered(let detail):
            return detail ?? String(localized: "Dropped before the timeout.")
        }
    }
}
