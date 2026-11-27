import LanFiCore
import AppKit
import SwiftUI

/// P1 per-process traffic, read-only and opt-in. Two `nettop` snapshots one
/// second apart give per-process receive/send deltas; the output never leaves
/// the Mac. Rows group by application or process and can terminate the owning
/// process or create a local block rule.
struct ProcessTrafficToolView: View {
    @ObservedObject var rules: ConnectionRulesModel
    @StateObject private var appHistory = AppTrafficHistoryModel.shared
    @StateObject private var domainAttribution = DomainAttributionModel.shared

    @AppStorage(AppSettingsKey.processTrafficEnabled.rawValue) private var enabled = false
    @State private var rows: [ProcessTrafficDelta] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var lastSampleAt: Date?
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var groupMode: TrafficGroupMode = .application
    @State private var expanded: Set<String> = []
    @State private var killTarget: KillTarget?
    @State private var showKillConfirmation = false
    @State private var ruleDraft: BlockRuleDraft?

    private struct KillTarget: Identifiable {
        let id = UUID()
        let pids: [Int]
        let label: String
    }

    private enum TableRow: Identifiable {
        case group(ProcessTrafficGroup)
        case process(ProcessTrafficDelta)

        var id: String {
            switch self {
            case .group(let group): return "g|\(group.id)"
            case .process(let row): return "p|\(row.id)"
            }
        }
    }

    // MARK: Grouping and sorting

    private var filtered: [ProcessTrafficDelta] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.process.localizedCaseInsensitiveContains(query)
                || String($0.pid).contains(query)
        }
    }

    private var groups: [ProcessTrafficGroup] {
        let source = filtered
        let grouped: [ProcessTrafficGroup]
        switch groupMode {
        case .application:
            grouped = TrafficGrouping.byApplication(source) { pid in
                ConnectionControlService.applicationName(for: pid)
            }
        case .process:
            grouped = TrafficGrouping.byProcess(source)
        }
        return grouped
    }

    private var tableRows: [TableRow] {
        var result: [TableRow] = []
        for group in groups {
            result.append(.group(group))
            if expanded.contains(group.id) {
                result.append(contentsOf: group.rows.map(TableRow.process))
            }
        }
        return result
    }

    private var matchingRows: [ProcessTrafficDelta] {
        rows.filter {
            ConnectionBlockRuleMatcher.matches(
                process: $0.process, pid: $0.pid, rules: rules.rules)
        }
    }

    private var totalReceived: Double {
        rows.reduce(0) { $0 + $1.receivedBytesPerSecond }
    }
    private var totalSent: Double {
        rows.reduce(0) { $0 + $1.sentBytesPerSecond }
    }

    // MARK: Body

    var body: some View {
        // As on the sockets tab, the summary and attribution cards plus the
        // table outgrow a short window once sampling starts; a plain VStack
        // overflowed and dragged the tab strip above the top edge.
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                if enabled {
                    controls
                }
                if let errorMessage {
                    ToolkitErrorBanner(message: errorMessage)
                }
                if let notice {
                    ruleNotice(notice)
                }
                if enabled, !matchingRows.isEmpty {
                    ruleBanner
                }
                if enabled {
                    summary
                    appHistoryCard
                    domainAttributionCard
                    table
                } else {
                    consentCard
                }
            }
            .appContentPadding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: enabled) {
            guard enabled else {
                rows = []
                return
            }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
        .confirmationDialog(
            "Terminate process?",
            isPresented: $showKillConfirmation,
            presenting: killTarget
        ) { target in
            Button("Terminate", role: .destructive) { terminate(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(
                "LanFi sends SIGTERM to \(target.label). Unsaved work in that process is lost, and macOS may refuse for processes you do not own."
            )
        }
        .sheet(item: $ruleDraft) { draft in
            BlockRuleEditorSheet(draft: draft) { rule in
                rules.add(rule)
                notice = String(localized: "Added rule: \(rule.scope.title) \(rule.value)")
            }
        }
    }

    private var consentCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Label("Per-process traffic is opt-in", systemImage: "hand.raised")
                    .font(.headline)
                Text(
                    "LanFi runs Apple's read-only nettop about once every ten seconds and keeps only process names, PIDs and byte deltas in memory. Nothing is uploaded, stored or used to identify traffic."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Toggle("Enable process traffic", isOn: $enabled)
                    .toggleStyle(.switch)
                Text("You can turn this off at any time; rates disappear immediately.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            AppButton(
                "Refresh", systemImage: "arrow.clockwise", tone: .primary,
                isBusy: isLoading, isEnabled: !isLoading
            ) {
                Task { await refresh() }
            }
            TextField("Filter by process or PID", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: DesignToken.Layout.controlWidthLarge)
            if isLoading { ProgressView().controlSize(.small) }
            Picker("Group", selection: $groupMode) {
                ForEach(TrafficGroupMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            AppIconButton(
                systemImage: expanded.count == groups.count
                    ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                label: "Expand or collapse every group"
            ) {
                if expanded.count == groups.count {
                    expanded.removeAll()
                } else {
                    expanded = Set(groups.map(\.id))
                }
            }
            .buttonStyle(.borderless)
            .help("Expand or collapse every group")
            .disabled(groups.isEmpty)
            if let lastSampleAt {
                Text("Sampled \(lastSampleAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Enabled", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
            AppButton("Copy", tone: .quiet) { copy() }
                .disabled(filtered.isEmpty)
        }
    }

    private var summary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Since the previous sample")
                HStack(spacing: DesignToken.Spacing.large) {
                    StatTile(value: "\(rows.count)", label: "Processes")
                    StatTile(
                        value: "\(groups.count)",
                        label: groupMode == .application ? "Apps" : "Process groups")
                    StatTile(
                        value: ProcessTrafficFormat.rate(totalReceived), label: "Download",
                        tint: AppPalette.info)
                    StatTile(
                        value: ProcessTrafficFormat.rate(totalSent), label: "Upload",
                        tint: AppPalette.warning)
                    Spacer()
                }
            }
        }
    }

    private func ruleNotice(_ text: String) -> some View {
        HStack(spacing: DesignToken.Spacing.small) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(AppPalette.info)
            Text(text).font(.caption)
            Spacer()
            AppButton("Dismiss", tone: .quiet) { notice = nil }
                .font(.caption2)
        }
        .padding(DesignToken.Spacing.compact)
        .background(
            DesignToken.Surface.accentFill,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }

    private var ruleBanner: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundColor(AppPalette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(matchingRows.count) processes match a block rule")
                    .font(.caption.weight(.semibold))
                Text("A rule marks processes; terminating them ends the process.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            AppButton("Terminate matches") {
                let pids = Array(Set(matchingRows.map(\.pid))).sorted()
                killTarget = KillTarget(
                    pids: pids,
                    label: pids.count == 1
                        ? String(localized: "1 process")
                        : String(localized: "\(pids.count) processes"))
                showKillConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(DesignToken.Spacing.compact)
        .background(
            DesignToken.Surface.warningFill,
            in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }

    /// P3.6: host names per app, from HAR hints and cached reverse DNS.
    private var domainAttributionCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Contacted domains")
                    if domainAttribution.isSampling { ProgressView().controlSize(.mini) }
                    Spacer()
                    AppButton("Refresh") {
                        Task { await domainAttribution.sampleNow() }
                    }
                    AppButton("Export CSV…", systemImage: "square.and.arrow.up") {
                        domainAttribution.exportCSV()
                    }
                }
                let summaries = domainAttribution.attribution.appSummaries()
                if summaries.isEmpty {
                    Text(
                        "No domains attributed yet. Names come from a HAR opened on HTTP Traffic and from cached reverse DNS of the remote endpoints in the connection list; sampling runs while Process Traffic is on."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(summaries, id: \.app) { entry in
                        HStack(spacing: DesignToken.Spacing.small) {
                            Text(entry.app).font(.caption).lineLimit(1)
                            Spacer(minLength: DesignToken.Spacing.small)
                            Text(entry.domain)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(entry.hits)")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                Text(
                    "Only host names are stored. Paths, query strings, cookies and payload are never read, and LanFi's own connections are excluded."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// P3.6: the week of hourly per-app totals this screen feeds.
    private var appHistoryCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "App history")
                    if appHistory.isSampling { ProgressView().controlSize(.mini) }
                    Spacer()
                    AppButton("Export CSV…", systemImage: "square.and.arrow.up") {
                        appHistory.exportCSV()
                    }
                }
                if appHistory.topAppsToday.isEmpty {
                    Text(
                        "Nothing recorded yet. Totals are sampled every 5 minutes while Process Traffic is on."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 24) {
                        ToolkitMetric(
                            title: "Today",
                            value: TrafficByteFormat.string(appHistory.todayTotal.total))
                        Spacer()
                    }
                    ForEach(appHistory.topAppsToday, id: \.app) { entry in
                        HStack(spacing: DesignToken.Spacing.small) {
                            Text(entry.app)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: DesignToken.Spacing.small)
                            Text(TrafficByteFormat.string(entry.volume.total))
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(
                        "Seven days of hourly byte totals per app, LanFi's own traffic excluded. Byte totals only; contacted hosts are attributed separately above, never from payload."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var table: some View {
        AppTable(
            columns: columns,
            rows: tableRows,
            initialKey: "download",
            ascending: false,
            grouping: AppTableGrouping(isSectionStart: { row in
                if case .group = row { return true }
                return false
            }),
            onActivate: activate,
            rowMenu: { trafficRowMenu($0) }
        )
        .frame(minHeight: ToolkitTableHeight.rows(tableRows.count, maximum: 640))
        .appTableSurface()
    }

    private var columns: [AppTableColumn<TableRow>] {
        [
            AppTableColumn(
                id: "process", title: "Process", minWidth: 170,
                value: { .text(processName($0)) }
            ) { processCell($0) },
            AppTableColumn(
                id: "pid", title: "PID", minWidth: AppColumnWidth.short,
                value: { .number(pidValue($0)) }
            ) { row in
                Text(pidLabel(row))
                    .monospacedDigit()
                    .foregroundColor(isGroup(row) ? .secondary : .primary)
            },
            AppTableColumn(
                id: "download", title: "Download", minWidth: AppColumnWidth.compact,
                value: { .number(download($0)) }
            ) { row in
                Text(ProcessTrafficFormat.rate(download(row)))
                    .monospacedDigit()
                    .foregroundColor(AppPalette.info)
            },
            AppTableColumn(
                id: "upload", title: "Upload", minWidth: AppColumnWidth.compact,
                value: { .number(upload($0)) }
            ) { row in
                Text(ProcessTrafficFormat.rate(upload(row)))
                    .monospacedDigit()
                    .foregroundColor(AppPalette.warning)
            },
            AppTableColumn(
                id: "transferred", title: "Transferred", minWidth: AppColumnWidth.compact,
                value: { .number(Double(transferred($0))) }
            ) { row in
                Text(ProcessTrafficFormat.bytes(transferred(row)))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            },
            AppTableColumn(
                id: "actions", title: "", minWidth: 58, isSortable: false,
                value: { _ in .none }
            ) { row in
                HStack(spacing: 4) {
                    Button {
                        prepareKill(row)
                    } label: {
                        Image(systemName: "xmark.octagon")
                            .foregroundColor(AppPalette.danger)
                    }
                    .buttonStyle(.borderless)
                    .help("Terminate this process")
                    blockMenu(row)
                }
            },
        ]
    }

    @ViewBuilder
    private func processCell(_ row: TableRow) -> some View {
        switch row {
        case .group(let group):
            HStack(spacing: 6) {
                Button {
                    toggle(group.id)
                } label: {
                    Image(
                        systemName: expanded.contains(group.id)
                            ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption2)
                    .frame(width: 12)
                }
                .buttonStyle(.plain)
                Text(group.name)
                    .font(.caption.weight(.medium))
                Text("\(group.rows.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        case .process(let process):
            HStack(spacing: 5) {
                if !rules.rules.isEmpty,
                    ConnectionBlockRuleMatcher.matches(
                        process: process.process, pid: process.pid, rules: rules.rules)
                {
                    Image(systemName: "shield.fill")
                        .font(.caption2)
                        .foregroundColor(AppPalette.warning)
                        .help("Matches a block rule")
                }
                Text(process.process)
            }
            .padding(.leading, 18)
        }
    }

    private func processName(_ row: TableRow) -> String {
        switch row {
        case .group(let group): return group.name
        case .process(let process): return process.process
        }
    }

    private func pidValue(_ row: TableRow) -> Int {
        switch row {
        case .group(let group): return group.rows.map(\.pid).min() ?? 0
        case .process(let process): return process.pid
        }
    }

    private func activate(_ row: TableRow) {
        guard case .group(let group) = row else { return }
        toggle(group.id)
    }

    @ViewBuilder
    private func trafficRowMenu(_ row: TableRow) -> some View {
        switch row {
        case .group(let group):
            Button(expanded.contains(group.id) ? "Collapse group" : "Expand group") {
                toggle(group.id)
            }
            Button("Copy group") {
                copyToPasteboard(
                    "\(group.name)\t\(group.rows.count)\t\(group.totalBytes)")
            }
            Divider()
            blockMenu(row)
            Button("Terminate \(group.name)", role: .destructive) { prepareKill(row) }
        case .process(let process):
            Button("Copy row") {
                copyToPasteboard(
                    "\(process.process)\t\(process.pid)\t\(process.totalBytes)")
            }
            Divider()
            blockMenu(row)
            Button("Terminate \(process.process)", role: .destructive) { prepareKill(row) }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Row helpers

    private func isGroup(_ row: TableRow) -> Bool {
        if case .group = row { return true }
        return false
    }

    private func download(_ row: TableRow) -> Double {
        switch row {
        case .group(let group): return group.receivedBytesPerSecond
        case .process(let process): return process.receivedBytesPerSecond
        }
    }

    private func upload(_ row: TableRow) -> Double {
        switch row {
        case .group(let group): return group.sentBytesPerSecond
        case .process(let process): return process.sentBytesPerSecond
        }
    }

    private func transferred(_ row: TableRow) -> UInt64 {
        switch row {
        case .group(let group): return group.totalBytes
        case .process(let process): return process.totalBytes
        }
    }

    private func pidLabel(_ row: TableRow) -> String {
        switch row {
        case .group(let group):
            let pids = group.rows.map(\.pid).sorted()
            if pids.count == 1 { return "\(pids[0])" }
            return "\(pids.prefix(2).map(String.init).joined(separator: ", "))…"
        case .process(let process): return "\(process.pid)"
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    private func prepareKill(_ row: TableRow) {
        switch row {
        case .group(let group):
            let pids = Array(Set(group.rows.map(\.pid))).sorted()
            killTarget = KillTarget(
                pids: pids,
                label: pids.count == 1
                    ? "\(group.name) (\(pids[0]))"
                    : "\(group.name) — \(pids.count) processes")
        case .process(let process):
            killTarget = KillTarget(
                pids: [process.pid], label: "\(process.process) (\(process.pid))")
        }
        showKillConfirmation = true
    }

    private func terminate(_ target: KillTarget) {
        var failures: [String] = []
        for pid in target.pids {
            let result = ConnectionControlService.terminate(pid: pid)
            if !result.succeeded { failures.append(result.message) }
        }
        if failures.isEmpty {
            notice = String(localized: "Sent SIGTERM to \(target.pids.count) process(es).")
        } else {
            errorMessage = failures.joined(separator: "\n")
        }
        Task { await refresh() }
    }

    @ViewBuilder
    private func blockMenu(_ row: TableRow) -> some View {
        let target: (process: String, pid: Int)? = {
            switch row {
            case .group(let group):
                guard let first = group.rows.first else { return nil }
                return (group.name, first.pid)
            case .process(let process):
                return (process.process, process.pid)
            }
        }()
        if let target {
            Menu {
                Button("Block application “\(appName(target.pid, fallback: target.process))”") {
                    add(.application, appName(target.pid, fallback: target.process))
                }
                Button("Block process “\(target.process)”") { add(.process, target.process) }
                Button("Block PID \(target.pid)") { add(.pid, "\(target.pid)") }
                Divider()
                Button("Custom rule…") {
                    ruleDraft = BlockRuleDraft(
                        scope: .process, value: target.process,
                        note: "From traffic row PID \(target.pid)")
                }
            } label: {
                Image(systemName: "shield")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Create a block rule from this row")
        }
    }

    private func appName(_ pid: Int, fallback: String) -> String {
        ConnectionControlService.applicationName(for: pid) ?? fallback
    }

    private func add(_ scope: BlockRuleScope, _ value: String) {
        let rule = ConnectionBlockRule(scope: scope, value: value)
        rules.add(rule)
        notice = String(localized: "Added rule: \(scope.title) \(value)")
    }

    // MARK: Data

    @MainActor
    private func refresh() async {
        guard enabled, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            rows = try await ProcessTrafficService.sample()
            lastSampleAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copy() {
        let text = filtered.map {
            "\($0.process)\t\($0.pid)\t\(ProcessTrafficFormat.bytes($0.receivedBytes))\t\(ProcessTrafficFormat.bytes($0.sentBytes))"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum TrafficGroupMode: String, CaseIterable, Identifiable {
    case application
    case process

    var id: String { rawValue }

    var title: String {
        switch self {
        case .application: return String(localized: "By app")
        case .process: return String(localized: "By process")
        }
    }
}
