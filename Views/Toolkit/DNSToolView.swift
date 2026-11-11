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
                switch model.tab {
                case .records:
                    recordsContent
                case .mail:
                    mailContent
                case .reports:
                    reportsContent
                }
            }
            .padding(18)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Domain", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Picker("Mode", selection: $model.tab) {
                        ForEach(DNSLookupTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    Picker("Resolver", selection: $model.resolverChoice) {
                        Text("System").tag("system")
                        Text("Cloudflare").tag("cloudflare")
                        Text("Google").tag("google")
                        Text("Custom").tag("custom")
                    }
                    .labelsHidden()
                    .frame(width: 125)
                    if model.resolverChoice == "custom" {
                        TextField("1.1.1.1", text: $model.customResolver)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    Spacer()
                    Button(runButtonTitle) { model.run() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isRunning)
                    Button("Copy") { copy() }
                        .buttonStyle(.bordered)
                        .disabled(!hasResult)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(!hasResult)
                    ToolkitStatusPill(text: statusText, tone: statusTone)
                }
                HStack(spacing: 12) {
                    if model.tab == .records {
                        Picker("Type", selection: $model.type) {
                            ForEach(DNSRecordType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }
                    Text(note)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var runButtonTitle: String {
        switch model.tab {
        case .records: return String(localized: "Look Up")
        case .mail: return String(localized: "Check")
        case .reports: return String(localized: "Report")
        }
    }

    private var note: String {
        switch model.tab {
        case .records:
            return String(
                localized:
                    "Records come back over UDP from the selected resolver; TTLs are shown exactly as received.")
        case .mail:
            return String(
                localized:
                    "Checks MX, SPF, DMARC and common DKIM selectors; every query goes to the selected resolver.")
        case .reports:
            return String(
                localized: "Turns the mail checks into a short posture report you can copy.")
        }
    }

    private var hasResult: Bool {
        switch model.tab {
        case .records: return model.result != nil
        case .mail, .reports: return model.mailReport != nil
        }
    }

    private var statusText: String {
        if model.isRunning {
            return model.tab == .records
                ? String(localized: "Resolving…") : String(localized: "Checking mail…")
        }
        switch model.tab {
        case .records:
            guard let result = model.result else { return String(localized: "Ready") }
            return String(
                format: String(localized: "%lld records · %lld ms"), result.records.count,
                result.milliseconds)
        case .mail, .reports:
            guard let report = model.mailReport else { return String(localized: "Ready") }
            return "\(report.passedChecks)/4"
        }
    }

    private var statusTone: ToolkitTone {
        if model.isRunning { return .running }
        switch model.tab {
        case .records:
            guard let result = model.result else { return .neutral }
            return result.records.isEmpty ? .warning : .good
        case .mail, .reports:
            guard let report = model.mailReport else { return .neutral }
            return report.issues.isEmpty ? .good : .warning
        }
    }

    // MARK: - Records

    @ViewBuilder
    private var recordsContent: some View {
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

    // MARK: - Mail

    @ViewBuilder
    private var mailContent: some View {
        if let report = model.mailReport {
            mailSummary(report)
            HStack(alignment: .top, spacing: 12) {
                mxCard(report)
                authenticationCard(report)
            }
            if !report.issues.isEmpty {
                issuesCard(report)
            }
        } else if !model.isRunning {
            ToolkitEmptyState(
                icon: "envelope.badge.shield.half.filled",
                title: "Check mail records",
                message:
                    "Reads MX, SPF, DMARC and common DKIM selectors, then explains what a receiver can verify."
            )
        }
    }

    private func mailSummary(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            HStack(spacing: 18) {
                ToolkitMetric(
                    title: "Checks",
                    value: "\(report.passedChecks)/4",
                    tint: report.passedChecks == 4 ? .green : .orange)
                ToolkitMetric(title: "MX records", value: "\(report.mx.count)")
                ToolkitMetric(
                    title: "DMARC",
                    value: report.dmarc?.policy.uppercased() ?? "—",
                    tint: report.hasDMARC ? .green : .orange)
                ToolkitMetric(
                    title: "DKIM", value: "\(report.dkim.count)",
                    tint: report.hasDKIM ? .green : .orange)
                Spacer()
            }
        }
    }

    private func mxCard(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 7) {
                ToolkitSectionLabel(text: "MX records")
                if report.mx.isEmpty {
                    Text("None")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    ForEach(report.mx, id: \.self) { record in
                        Text(record)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authenticationCard(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 7) {
                ToolkitSectionLabel(text: "Authentication")
                checkRow("SPF", report.hasSPF, report.spf)
                checkRow(
                    "DMARC", report.hasDMARC,
                    report.dmarc.map { "p=\($0.policy)" })
                checkRow(
                    "DKIM", report.hasDKIM,
                    report.dkim.isEmpty
                        ? nil : report.dkim.map(\.selector).joined(separator: ", "))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checkRow(_ title: String, _ passed: Bool, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(passed ? .green : .orange)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
                .frame(width: 52, alignment: .leading)
            Text(detail ?? String(localized: "Missing"))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func issuesCard(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 6) {
                ToolkitSectionLabel(text: "Issues")
                ForEach(report.issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Reports

    @ViewBuilder
    private var reportsContent: some View {
        if let report = model.mailReport {
            reportHeader(report)
            reportChecks(report)
            if !report.issues.isEmpty {
                issuesCard(report)
            }
        } else if !model.isRunning {
            ToolkitEmptyState(
                icon: "doc.text.magnifyingglass",
                title: "Build a mail report",
                message:
                    "Runs the MX/SPF/DMARC/DKIM checks and turns them into a short, copyable report."
            )
        }
    }

    private func reportHeader(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            HStack(spacing: 16) {
                Text("\(report.passedChecks)/4")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(report.passedChecks == 4 ? .green : .orange)
                    .frame(width: 90)
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.domain)
                        .font(.title3.bold())
                    Text(
                        report.issues.isEmpty
                            ? String(localized: "All core mail checks pass.")
                            : String(
                                format: String(localized: "%lld issues found."),
                                report.issues.count)
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func reportChecks(_ report: DNSMailReport) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Checks")
                reportRow("MX", report.hasMX)
                reportRow("SPF", report.hasSPF)
                reportRow("DMARC", report.hasDMARC)
                reportRow("DKIM", report.hasDKIM)
            }
        }
    }

    private func reportRow(_ title: String, _ passed: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .orange)
            Text(title)
                .font(.callout)
            Spacer()
            Text(passed ? String(localized: "Pass") : String(localized: "Missing"))
                .font(.caption)
                .foregroundColor(passed ? .secondary : .orange)
        }
    }

    // MARK: - Shared

    private func summaryRow(_ title: LocalizedStringKey, _ value: String) -> some View {
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
        switch model.tab {
        case .records:
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
        case .mail, .reports:
            guard let report = model.mailReport else { return }
            var lines = [
                "LanFi mail report \(report.domain)", "",
                "MX: \(report.mx.joined(separator: ", "))",
                "SPF: \(report.spf ?? "missing")",
                "DMARC: \(report.dmarc?.raw ?? "missing")",
                "DKIM: \(report.dkim.map(\.selector).joined(separator: ", "))",
                "Checks: \(report.passedChecks)/4",
            ]
            if !report.issues.isEmpty {
                lines.append("")
                lines.append(contentsOf: report.issues.map { "! \($0)" })
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }
    }
}
