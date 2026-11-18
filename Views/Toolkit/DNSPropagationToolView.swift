import SwiftUI

struct DNSPropagationToolView: View {
    @ObservedObject var model: DNSPropagationToolModel

    private enum SortKey: String, CaseIterable, Identifiable {
        case resolver, value, queryTime, status
        var id: String { rawValue }
        var title: String {
            switch self {
            case .resolver: return String(localized: "Resolver")
            case .value: return String(localized: "Value")
            case .queryTime: return String(localized: "Query time")
            case .status: return String(localized: "Status")
            }
        }
    }

    @State private var sortKey: SortKey = .resolver
    @State private var sortAscending = true

    private func sortedResults(_ rows: [DNSPropagationResult]) -> [DNSPropagationResult] {
        let ordered = rows.sorted { lhs, rhs in
            switch sortKey {
            case .resolver:
                return lhs.resolver.name.localizedStandardCompare(rhs.resolver.name)
                    == .orderedAscending
            case .value:
                return lhs.values.joined(separator: ", ")
                    .localizedStandardCompare(rhs.values.joined(separator: ", "))
                    == .orderedAscending
            case .queryTime: return lhs.milliseconds < rhs.milliseconds
            case .status: return (lhs.isSuccess ? 1 : 0) < (rhs.isSuccess ? 1 : 0)
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
            .appContentPadding()
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
                    TableSortControl(
                        options: SortKey.allCases.map { ($0, $0.title) },
                        selection: $sortKey, ascending: $sortAscending)
                    Spacer()
                    Text(model.host)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                Table(sortedResults(model.results)) {
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
                    }
                    TableColumn("Query time") { result in
                        Text(result.isSuccess ? "\(result.milliseconds) ms" : "—")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(95)
                }
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
