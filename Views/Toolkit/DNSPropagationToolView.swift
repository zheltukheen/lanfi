import SwiftUI

struct DNSPropagationToolView: View {
    @ObservedObject var model: DNSPropagationToolModel

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
                        icon: "globe",
                        title: "Check DNS propagation",
                        message:
                            "Asks six public resolvers for the same record and shows whether they agree. Useful after changing DNS."
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
                    TextField("Domain", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Picker("Type", selection: $model.type) {
                        ForEach(DNSRecordType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 95)
                    TextField("Expected value (optional)", text: $model.expected)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Spacer()
                    if model.isRunning {
                        Button("Stop") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Check") { model.run() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Copy") { copy() }
                        .buttonStyle(.bordered)
                        .disabled(model.results.isEmpty)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.results.isEmpty)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                Text("Six public resolvers · each answer comes from the resolver's nearest location.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return String(localized: "Checking…") }
        guard !model.results.isEmpty else { return String(localized: "Ready") }
        let summary = model.summary
        if !model.expected.isEmpty {
            return String(
                format: String(localized: "%lld of %lld match"),
                summary.matchingCount, model.results.count)
        }
        return String(
            format: String(localized: "%lld of %lld answers"),
            summary.successfulCount, model.results.count)
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard !model.results.isEmpty else { return .neutral }
        let summary = model.summary
        if !model.expected.isEmpty {
            return summary.allMatch ? .good : .warning
        }
        return summary.consistent ? .good : .warning
    }

    private var summary: some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(
                    title: "Answers",
                    value: "\(model.summary.successfulCount)/\(model.results.count)")
                ToolkitMetric(
                    title: "Matching",
                    value: model.expected.isEmpty
                        ? "—" : "\(model.summary.matchingCount)/\(model.results.count)",
                    tint: model.expected.isEmpty
                        ? .primary : (model.summary.allMatch ? .green : .orange))
                ToolkitMetric(
                    title: "Consistent",
                    value: model.summary.consistent ? "Yes" : "No",
                    tint: model.summary.consistent ? .green : .orange)
                ToolkitMetric(title: "Record", value: model.type.label)
                Spacer()
            }
        }
    }

    private var resultsTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Resolvers")
                    Spacer()
                    Text(model.host)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(model.results) {
                    TableColumn("Resolver") { result in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(result.isSuccess ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            Text(result.resolver.name)
                                .font(.caption)
                            Text(result.resolver.address ?? "")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                    }
                    TableColumn("Value") { result in
                        VStack(alignment: .leading, spacing: 1) {
                            if let error = result.error {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .lineLimit(2)
                            } else if result.values.isEmpty {
                                Text("No records")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(result.values, id: \.self) { value in
                                    Text(value)
                                        .font(.caption.monospaced())
                                        .foregroundColor(
                                            model.expected.isEmpty
                                                || value.caseInsensitiveCompare(model.expected)
                                                    == .orderedSame
                                                ? .primary : .orange
                                        )
                                }
                            }
                        }
                    }
                    TableColumn("Query time") { result in
                        Text(result.isSuccess ? "\(result.milliseconds) ms" : "—")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(95)
                }
                .frame(height: min(CGFloat(model.results.count) * 30 + 52, 420))
            }
        }
    }

    private func copy() {
        var lines = [
            "LanFi DNS propagation \(model.host) \(model.type.label)", "",
        ]
        for result in model.results {
            let value = result.error ?? result.values.joined(separator: ", ")
            lines.append("\(result.resolver.name)\t\(result.resolver.address ?? "")\t\(value)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
