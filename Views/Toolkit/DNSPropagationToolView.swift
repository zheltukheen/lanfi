import SwiftUI

struct DNSPropagationToolView: View {
    @ObservedObject var model: DNSPropagationToolModel
    /// Embedded in the DNS tab: no second scroll view or page padding.
    var embedded = false

    var body: some View {
        if embedded {
            content
        } else {
            ScrollView { content.appContentPadding() }
        }
    }

    private var content: some View {
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
    }

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToolTargetField(
                        text: $model.host, placeholder: "Domain", maxWidth: 220,
                        onSubmit: { model.run() })
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
                        AppButton("Stop", tone: .secondary) { model.stop() }
                    } else {
                        AppButton("Check", tone: .primary) { model.run() }
                    }
                    AppButton("Copy", tone: .secondary) { copy() }
                        .disabled(model.results.isEmpty)
                    AppButton("Clear", tone: .quiet) { model.clear() }
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
                    value: model.summary.consistent ? String(localized: "Yes") : String(localized: "No"),
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
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "resolver", title: "Resolver", minWidth: 200,
                            value: { .text($0.resolver.name) }
                        ) { result in
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
                        },
                        AppTableColumn(
                            id: "value", title: "Value", minWidth: 220,
                            value: { .text($0.values.joined(separator: ", ")) }
                        ) { result in
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
                                    let joined = result.values.joined(separator: ", ")
                                    Text(joined)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundColor(
                                            model.expected.isEmpty
                                                || result.values.allSatisfy({
                                                    $0.caseInsensitiveCompare(model.expected)
                                                        == .orderedSame
                                                })
                                                ? .primary : .orange
                                        )
                                }
                            }
                        },
                        AppTableColumn(
                            id: "queryTime", title: "Query time", minWidth: 95,
                            value: { .number($0.milliseconds) }
                        ) { result in
                            Text(result.isSuccess ? "\(result.milliseconds) ms" : "—")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        },
                    ],
                    rows: model.results, initialKey: "resolver"
                )
                .frame(
                    height: ToolkitTableHeight.rows(
                        model.results.count, row: 32, header: 42, minimum: 230,
                        maximum: 440))
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
