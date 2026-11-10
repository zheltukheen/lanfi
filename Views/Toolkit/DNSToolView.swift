import AppKit
import SwiftUI

struct DNSToolView: View {
    @ObservedObject var model: DNSToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let result = model.result {
                    if result.records.isEmpty {
                        ToolkitEmptyState(
                            icon: "tray",
                            title: "No records",
                            message: "The resolver returned no \(model.type.label) records for \(result.host)."
                        )
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            recordsTable(result)
                            summary(result)
                                .frame(width: 230)
                        }
                    }
                } else if !model.isRunning {
                    ToolkitEmptyState(
                        icon: "magnifyingglass",
                        title: "Look up a record",
                        message:
                            "Query A, AAAA, MX, TXT, NS, SOA, CNAME, SRV and CAA records from the system resolver or a public one."
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
                        .frame(maxWidth: 260)
                    Picker("Type", selection: $model.type) {
                        ForEach(DNSRecordType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    Picker("Resolver", selection: $model.resolverChoice) {
                        Text("System").tag("system")
                        Text("Cloudflare").tag("cloudflare")
                        Text("Google").tag("google")
                        Text("Custom").tag("custom")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    if model.resolverChoice == "custom" {
                        TextField("1.1.1.1", text: $model.customResolver)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 130)
                    }
                    Spacer()
                    Button("Look Up") { model.run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRunning)
                    Button("Copy") { copy() }
                        .buttonStyle(.bordered)
                        .disabled(model.result == nil)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.result == nil)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                Text("Records come back over UDP from the selected resolver; TTLs are shown exactly as received.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusText: String {
        if model.isRunning { return "Resolving…" }
        guard let result = model.result else { return "Ready" }
        return "\(result.records.count) records · \(result.milliseconds) ms"
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        guard let result = model.result else { return .neutral }
        return result.records.isEmpty ? .warning : .good
    }

    private func recordsTable(_ result: DNSLookupResult) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Answers")
                    Spacer()
                    Text(result.host)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(result.records) {
                    TableColumn("Type") { record in
                        ToolkitTypeBadge(
                            text: record.type.label,
                            color: ToolkitTypeColor.color(for: record.type))
                    }
                    .width(66)
                    TableColumn("Name") { record in
                        Text(record.name)
                            .font(.caption.monospaced())
                    }
                    TableColumn("TTL") { record in
                        Text("\(record.ttl)s")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(70)
                    TableColumn("Priority") { record in
                        Text(record.priority.map(String.init) ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(64)
                    TableColumn("Value") { record in
                        Text(record.value)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .frame(height: min(CGFloat(result.records.count) * 24 + 28, 520))
            }
        }
    }

    private func summary(_ result: DNSLookupResult) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                ToolkitSectionLabel(text: "Result")
                summaryRow("Domain", result.host)
                summaryRow("Resolver", result.resolver)
                summaryRow("Query time", "\(result.milliseconds) ms")
                summaryRow("Records", "\(result.records.count)")
                Divider()
                let counts = Dictionary(grouping: result.records, by: \.type)
                ForEach(DNSRecordType.allCases.filter { counts[$0] != nil }) { type in
                    HStack {
                        ToolkitTypeBadge(
                            text: type.label,
                            color: ToolkitTypeColor.color(for: type))
                        Spacer()
                        Text("\(counts[type]?.count ?? 0)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func copy() {
        guard let result = model.result else { return }
        var lines = [
            "LanFi DNS \(result.host) · \(result.resolver) · \(result.milliseconds) ms", "",
        ]
        for record in result.records {
            lines.append(
                "\(record.type.label)\t\(record.name)\t\(record.ttl)\t\(record.priority.map(String.init) ?? "-")\t\(record.value)"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
