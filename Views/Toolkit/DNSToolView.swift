import AppKit
import SwiftUI
import LanFiCore

struct DNSToolView: View {
    @ObservedObject var model: DNSToolModel
    @ObservedObject var propagation: DNSPropagationToolModel
    @ObservedObject var toolkit: ToolkitViewModel
    @StateObject private var benchmark = DNSBenchmarkModel()
    @StateObject private var resolverSwitch = DNSResolverSwitchModel()

    private enum Section: String, CaseIterable, Identifiable {
        case lookup, propagation
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lookup: return String(localized: "Lookup")
            case .propagation: return String(localized: "Propagation")
            }
        }
    }

    @State private var section: Section = .lookup

    var body: some View {
        VStack(spacing: 0) {
            // The Lookup/Propagation split is the same tab strip as Whois,
            // Traceroute and Network Monitor: this screen used to carry a
            // segmented picker inside its scrolling content instead.
            ToolkitHeaderBar {
                AppTabBar(
                    sections: [
                        .init(
                            id: "dns", title: nil,
                            items: [
                                .init(
                                    id: Section.lookup.rawValue, title: "Lookup",
                                    icon: "magnifyingglass"),
                                .init(
                                    id: Section.propagation.rawValue, title: "Propagation",
                                    icon: "globe"),
                            ])
                    ],
                    selection: Binding(
                        get: { section.rawValue },
                        set: { section = Section(rawValue: $0) ?? section }),
                    showsGroupTitles: false)
            } trailing: {
                Text(
                    "One name, two questions: what does it resolve to now, and does every resolver agree?"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if section == .lookup {
                        controls
                        if let error = model.errorMessage {
                            ToolkitErrorBanner(message: error)
                        }
                        benchmarkCard
                        switch model.tab {
                        case .records:
                            recordsContent
                        case .mail:
                            mailContent
                        case .reports:
                            reportsContent
                        }
                    } else {
                        DNSPropagationToolView(model: propagation, embedded: true)
                    }
                }
                .appContentPadding()
            }
        }
        .onAppear {
            syncSection(with: toolkit.selection)
            syncPropagationHost()
            Task { await resolverSwitch.load() }
        }
        .sheet(item: $resolverSwitch.pendingPlan) { plan in
            confirmationSheet(plan)
        }
        .onChange(of: toolkit.selection) { selection in syncSection(with: selection) }
        .onChange(of: model.host) { _ in syncPropagationHost() }
        .onChange(of: propagation.host) { _ in
            if section == .propagation, propagation.host != model.host {
                model.host = propagation.host
            }
        }
    }

    /// A deep link to the propagation tool opens its own tab.
    private func syncSection(with tool: ToolboxTool) {
        if tool == .dnsPropagation { section = .propagation }
        if tool == .dnsLookup { section = .lookup }
    }

    private func syncPropagationHost() {
        guard !model.host.isEmpty, propagation.host != model.host else { return }
        propagation.host = model.host
    }

    // MARK: - Controls

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ToolTargetField(
                        text: $model.host, placeholder: "Domain", onSubmit: { model.run() })
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
                    AppButton(localized: runButtonTitle, tone: .primary, isEnabled: !model.isRunning) {
                        model.run()
                    }
                    if model.tab == .records {
                        AppButton("Compare", tone: .secondary) { model.compare() }
                            .disabled(model.isComparing || model.isRunning)
                    }
                    AppButton("Copy", tone: .secondary) { copy() }
                        .disabled(!hasResult)
                    AppButton("Clear", tone: .quiet) { model.clear() }
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

    // MARK: - Resolver benchmark

    private var benchmarkCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Resolver benchmark")
                    Spacer()
                    if benchmark.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    AppButton(benchmark.isRunning ? "Stop" : "Benchmark", tone: .secondary) {
                        if benchmark.isRunning { benchmark.stop() } else { benchmark.run() }
                    }
                }
                Text(
                    "Median time to resolve three names, three rounds each, through the system, Cloudflare, Google and Quad9 resolvers. Measuring is read-only; switching is a separate opt-in below and always asks for the current and the pending servers first."
                )
                .font(.caption2)
                .foregroundColor(.secondary)

                if let report = benchmark.report, !report.results.isEmpty {
                    let rows = report.ranked
                    AppTable(columns: benchmarkColumns, rows: rows, initialKey: "median")
                        .frame(height: min(CGFloat(rows.count) * 30 + 34, 200))
                    if let fastest = report.fastest {
                        Text("Fastest: \(fastest.name) · \(Self.milliseconds(fastest.medianMilliseconds))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if !benchmark.isRunning {
                    Text("Run the benchmark to compare resolvers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                switchControls
            }
        }
    }

    private var benchmarkColumns: [AppTableColumn<DNSBenchmarkResult>] {
        [
            AppTableColumn(
                id: "resolver", title: "Resolver", minWidth: 150,
                value: { .text($0.name) },
                cell: { row in
                    AnyView(Text(row.name).font(.caption).lineLimit(1))
                }),
            AppTableColumn(
                id: "median", title: "Median", minWidth: 80, alignment: .trailing,
                value: { .number($0.medianMilliseconds) },
                cell: { row in
                    AnyView(
                        Text(Self.milliseconds(row.medianMilliseconds))
                            .font(.caption.monospacedDigit()))
                }),
            AppTableColumn(
                id: "range", title: "Range", minWidth: 100, alignment: .trailing,
                value: { .number($0.fastestMilliseconds) },
                cell: { row in
                    // Plain String, not an interpolated localizable key.
                    let range = row.fastestMilliseconds.map { fastest in
                        "\(Self.milliseconds(fastest))–\(Self.milliseconds(row.slowestMilliseconds))"
                    }
                    return AnyView(
                        Text(range ?? "—")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "lookups", title: "Lookups", minWidth: 70, alignment: .trailing,
                value: { .number(Double($0.lookupCount)) },
                cell: { row in
                    AnyView(
                        Text("\(row.lookupCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary))
                }),
            AppTableColumn(
                id: "failures", title: "Failures", minWidth: 70, alignment: .trailing,
                value: { .number(Double($0.failures)) },
                cell: { row in
                    AnyView(
                        Text("\(row.failures)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(row.failures > 0 ? .orange : .secondary))
                }),
            AppTableColumn(
                id: "switch", title: "System", minWidth: 86, isSortable: false,
                value: { _ in .text("") },
                cell: { row in
                    if row.canSwitch {
                        Button("Use…") {
                            resolverSwitch.prepare(servers: row.switchServers, name: row.name)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    } else {
                        Text("—").font(.caption2).foregroundColor(.secondary)
                    }
                }),
        ]
    }

    /// P3.5: the current resolver, the service it belongs to, and the two
    /// explicit actions. Nothing switches without the confirmation sheet.
    private var switchControls: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            HStack(spacing: DesignToken.Spacing.small) {
                ToolkitSectionLabel(text: "System resolver")
                Spacer()
                if resolverSwitch.isWorking { ProgressView().controlSize(.small) }
            }
            HStack(spacing: DesignToken.Spacing.small) {
                if resolverSwitch.services.count > 1 {
                    Picker(
                        "Service",
                        selection: Binding(
                            get: { resolverSwitch.selectedService },
                            set: { value in Task { await resolverSwitch.selectService(value) } })
                    ) {
                        ForEach(resolverSwitch.services, id: \.self) { service in
                            Text(service).tag(service)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                } else {
                    Text(resolverSwitch.selectedService)
                        .font(.caption)
                }
                Text(resolverSwitch.currentLabel)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Spacer()
                AppButton("Revert to previous…", isEnabled: resolverSwitch.backup != nil) {
                    resolverSwitch.prepareRevert()
                }
                AppButton("Refresh", tone: .quiet) {
                    Task { await resolverSwitch.load() }
                }
            }
            if let message = resolverSwitch.message {
                Text(message).font(.caption2).foregroundColor(.secondary)
            }
            if let error = resolverSwitch.errorMessage {
                Text(error).font(.caption2).foregroundColor(AppPalette.danger)
            }
            Text(
                "Switching changes the DNS servers for the chosen network service, flushes the cache and asks macOS for administrator authorization. It is never automatic; Revert restores what was there before the change (DHCP when no manual servers were set)."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confirmationSheet(_ plan: DNSResolverPlan) -> some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack(spacing: DesignToken.Spacing.small) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.isRevertToAutomatic ? "Restore automatic DNS" : "Switch DNS resolver")
                        .font(.headline)
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: DesignToken.Spacing.tight) {
                LabeledContent("Network service", value: plan.service)
                LabeledContent(
                    "Current",
                    value: plan.currentServers.isEmpty
                        ? "Automatic (DHCP)" : plan.currentServers.joined(separator: ", "))
                LabeledContent(
                    "Pending",
                    value: plan.newServers.isEmpty
                        ? "Automatic (DHCP)" : plan.newServers.joined(separator: ", "))
            }
            .font(.caption)
            .padding(DesignToken.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
            Text(
                "macOS will ask for administrator authorization. The change persists across restarts; the DNS cache is flushed as part of it."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { resolverSwitch.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(resolverSwitch.pendingApply)
                Button(plan.isRevertToAutomatic ? "Restore DHCP" : "Switch") {
                    Task { await resolverSwitch.apply() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(resolverSwitch.pendingApply)
            }
        }
        .padding(DesignToken.Spacing.section)
        .frame(width: 460)
    }

    private static func milliseconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f ms", value)
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
        case .records: return model.result != nil || model.comparison != nil
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
        if let comparison = model.comparison {
            comparisonCard(comparison)
        } else if model.isComparing {
            ToolkitCard {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Querying every resolver over UDP and DoH…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } else if let result = model.result {
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
                if !model.notes.isEmpty {
                    notesCard
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

    /// Explains the shape of the answer instead of leaving the user to guess
    /// whether a private or fake address is normal.
    private var notesCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Why this answer")
                ForEach(model.notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(
                            systemName: note.kind == .warning
                                ? "exclamationmark.triangle.fill" : "info.circle"
                        )
                        .font(.caption2)
                        .foregroundColor(note.kind == .warning ? AppPalette.warning : AppPalette.muted)
                        Text(note.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func comparisonCard(_ comparison: DNSComparison) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ToolkitSectionLabel(text: "Resolver comparison")
                    Spacer()
                    Text("\(comparison.host) · \(comparison.type.label)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    ToolkitStatusPill(
                        text: comparison.summary,
                        tone: comparison.answersDisagree ? .warning : .good)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "resolver", title: "Resolver", minWidth: 150,
                            value: { .text($0.name) }
                        ) { entry in
                            Text(entry.name)
                                .font(.caption)
                        },
                        AppTableColumn(
                            id: "transport", title: "Transport", minWidth: 90,
                            value: { .text($0.transport.label) }
                        ) { entry in
                            ToolkitTypeBadge(
                                text: entry.transport.label,
                                color: entry.transport == .udp ? AppPalette.muted : AppPalette.info)
                        },
                        AppTableColumn(
                            id: "answers", title: "Answers", minWidth: 260,
                            value: { .text($0.answerText) }
                        ) { entry in
                            Text(entry.answerText)
                                .font(.caption.monospaced())
                                .foregroundColor(entry.failure == nil ? .primary : .secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        },
                        AppTableColumn(
                            id: "time", title: "Time", minWidth: 70,
                            value: { .number($0.milliseconds) }
                        ) { entry in
                            Text("\(entry.milliseconds) ms")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        },
                    ],
                    rows: comparison.entries, initialKey: "resolver"
                )
                .frame(
                    height: ToolkitTableHeight.rows(
                        comparison.entries.count, row: 26, header: 40, minimum: 210,
                        maximum: 540))

                if comparison.failedCount > 0 {
                    Text(
                        "\(comparison.failedCount) of \(comparison.entries.count) resolvers did not answer; that is reported, not hidden."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, DesignToken.Spacing.card)
                    .padding(.vertical, DesignToken.Spacing.small)
                }
            }
        }
    }

    /// Country and network for the resolved addresses. Absent until the
    /// annotation arrives, so the table never shows an empty column.
    private var locationColumn: [AppTableColumn<DNSRecord>] {
        guard !model.annotations.isEmpty else { return [] }
        let annotations = model.annotations
        return [
            AppTableColumn(
                id: "location", title: String(localized: "Location"), minWidth: 190,
                value: { .text(annotations[$0.value]?.summary ?? "") }
            ) { record in
                Text(annotations[record.value]?.summary ?? "—")
                    .font(.caption2)
                    .foregroundColor(
                        annotations[record.value] == nil ? AppPalette.muted : .primary
                    )
                    .lineLimit(1)
            }
        ]
    }

    /// The answer columns are their own property: folding them into one
    /// `AppTable` expression pushed the type checker past its limit on an
    /// older toolchain.
    private var recordColumns: [AppTableColumn<DNSRecord>] {
        [
            AppTableColumn(
                id: "type", title: "Type", minWidth: 66,
                value: { .text($0.type.label) }
            ) { record in
                ToolkitTypeBadge(
                    text: record.type.label,
                    color: ToolkitTypeColor.color(for: record.type))
            },
            AppTableColumn(
                id: "name", title: "Name", minWidth: 140,
                value: { .text($0.name) }
            ) { record in
                Text(record.name)
                    .font(.caption.monospaced())
            },
            AppTableColumn(
                id: "ttl", title: "TTL", minWidth: 70,
                value: { .number(Int($0.ttl)) }
            ) { record in
                Text("\(record.ttl)s")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            },
            AppTableColumn(
                id: "priority", title: "Priority", minWidth: 64,
                value: { .number($0.priority.map(Int.init)) }
            ) { record in
                Text(record.priority.map(String.init) ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            },
            AppTableColumn(
                id: "value", title: "Value", minWidth: 200,
                value: { .text($0.value) }
            ) { record in
                Text(record.value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            },
        ]
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
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                AppTable(
                    columns: recordColumns + locationColumn,
                    rows: result.records, initialKey: "type"
                )
                .frame(
                    height: ToolkitTableHeight.rows(
                        result.records.count, row: 26, header: 40, minimum: 210,
                        maximum: 540))
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
            if let comparison = model.comparison {
                copyComparison(comparison)
                return
            }
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

    /// Copies the resolver comparison that is on screen.
    private func copyComparison(_ comparison: DNSComparison) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(comparison.exportText, forType: .string)
    }
}
