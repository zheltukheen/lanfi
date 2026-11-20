import AppKit
import SwiftUI

/// P1.8 Connections: read-only `lsof -nP -iTCP` grouped by socket or process.
/// Every row can terminate its owning process and create a local block rule;
/// nothing is installed in the kernel, so the screen says what it can and
/// cannot enforce.
struct OpenConnectionsToolView: View {
    @ObservedObject var rules: ConnectionRulesModel

    @StateObject private var watcher = ListenerWatcher.shared
    @StateObject private var descriptions = ServiceDescriptionResolver.shared

    @State private var connections: [OpenConnection] = []
    @State private var includeListeners = false
    @State private var includeUDP = false
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var groupMode: SocketGroupMode = .socket
    @State private var expanded: Set<String> = []
    @State private var killTarget: KillTarget?
    @State private var showKillConfirmation = false
    @State private var ruleDraft: BlockRuleDraft?

    // MARK: Rows

    private enum TableRow: Identifiable {
        case group(ConnectionSocketGroup)
        case connection(OpenConnection)

        var id: String {
            switch self {
            case .group(let group): return "g|\(group.id)"
            case .connection(let connection): return "c|\(connection.id)"
            }
        }
    }

    private struct KillTarget: Identifiable {
        let id = UUID()
        let pids: [Int]
        let label: String
    }

    private var filtered: [OpenConnection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return connections }
        return connections.filter {
            $0.process.localizedCaseInsensitiveContains(query)
                || $0.remote.localizedCaseInsensitiveContains(query)
                || $0.local.localizedCaseInsensitiveContains(query)
                || String($0.pid).contains(query)
        }
    }

    private var groups: [ConnectionSocketGroup] {
        let rows = filtered
        let grouped: [ConnectionSocketGroup]
        switch groupMode {
        case .socket: grouped = ConnectionGrouping.bySocket(rows)
        case .process: grouped = ConnectionGrouping.byProcess(rows)
        }
        return grouped
    }

    private var tableRows: [TableRow] {
        var rows: [TableRow] = []
        for group in groups {
            rows.append(.group(group))
            if expanded.contains(group.id) {
                rows.append(contentsOf: group.connections.map(TableRow.connection))
            }
        }
        return rows
    }

    private var matchingConnections: [OpenConnection] {
        ConnectionBlockRuleMatcher.matching(connections, rules: rules.rules)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            controls
            if let errorMessage {
                ToolkitErrorBanner(message: errorMessage)
            }
            if let notice {
                ruleNotice(notice)
            }
            if !matchingConnections.isEmpty {
                ruleBanner
            }
            summary
            watcherCard
            table
        }
        .appContentPadding()
        .task {
            watcher.restoreFromSettings()
            await refresh()
        }
        .confirmationDialog(
            "Terminate process?",
            isPresented: $showKillConfirmation,
            presenting: killTarget
        ) { target in
            Button("Terminate", role: .destructive) {
                terminate(target)
            }
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

    private var controls: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            AppButton(
                "Refresh", systemImage: "arrow.clockwise", tone: .primary,
                isBusy: isLoading, isEnabled: !isLoading
            ) {
                Task { await refresh() }
            }
            Toggle("Include listening sockets", isOn: $includeListeners)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: includeListeners) { _ in
                    Task { await refresh() }
                }
            Toggle("Include UDP listeners", isOn: $includeUDP)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Adds UDP sockets, which answer clients without a TCP listener.")
                .onChange(of: includeUDP) { _ in
                    Task { await refresh() }
                }
            Toggle("Watch listeners", isOn: watchBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Samples listening sockets every 30 s and notifies when one appears or closes.")
            TextField("Filter by process, address or PID", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: DesignToken.Layout.controlWidthLarge)
            if isLoading { ProgressView().controlSize(.small) }
            Picker("Group", selection: $groupMode) {
                ForEach(SocketGroupMode.allCases) { mode in
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
            .disabled(groups.isEmpty)
            Spacer()
            AppButton("Copy", tone: .quiet) { copy() }
                .disabled(filtered.isEmpty)
        }
    }

    private var summary: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Processes")
                if connections.isEmpty {
                    Text(
                        "No TCP connections were returned. lsof can hide other users' sockets without root; this screen never asks for a password."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: DesignToken.Spacing.large) {
                        StatTile(value: "\(connections.count)", label: "Connections")
                        StatTile(
                            value: "\(OpenConnectionsParser.byProcess(connections).count)",
                            label: "Processes", tint: AppPalette.info)
                        StatTile(
                            value: "\(connections.filter(\.isListener).count)", label: "Listening",
                            tint: AppPalette.warning)
                        StatTile(
                            value: "\(connections.filter { $0.exposure.isLANReachable }.count)",
                            label: "Reachable", tint: AppPalette.danger)
                        StatTile(
                            value: "\(groups.count)",
                            label: groupMode == .socket ? "Sockets" : "Process groups")
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignToken.Spacing.tight) {
                            ForEach(OpenConnectionsParser.byProcess(connections), id: \.process) {
                                group in
                                Text("\(group.process) · \(group.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, DesignToken.Spacing.small)
                                    .padding(.vertical, DesignToken.Spacing.hairline)
                                    .background(
                                        Color.secondary.opacity(0.10), in: Capsule())
                            }
                        }
                    }
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
                Text("\(matchingConnections.count) sockets match a block rule")
                    .font(.caption.weight(.semibold))
                Text("A rule marks sockets; terminating them ends the owning processes.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            AppButton("Terminate matches") {
                let pids = Array(Set(matchingConnections.map(\.pid))).sorted()
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
            Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
    }

    private var table: some View {
        AppTable(
            columns: columns,
            rows: tableRows,
            initialKey: "process",
            grouping: AppTableGrouping(isSectionStart: { row in
                if case .group = row { return true }
                return false
            }),
            onActivate: activate,
            rowMenu: { rowMenu($0) }
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
                Text(pidLabel(row)).monospacedDigit()
                    .foregroundColor(isGroup(row) ? .secondary : .primary)
            },
            AppTableColumn(
                id: "user", title: "User", minWidth: AppColumnWidth.compact,
                value: { .text(primary($0)?.user) }
            ) { Text(primary($0)?.user ?? "—") },
            AppTableColumn(
                id: "service", title: "Service", minWidth: AppColumnWidth.medium,
                value: { .text(serviceTitle($0)) }
            ) { serviceLabel($0) },
            AppTableColumn(
                id: "proto", title: "Proto", minWidth: AppColumnWidth.short,
                value: { .text(protoLabel($0)) }
            ) { Text(protoLabel($0)) },
            AppTableColumn(
                id: "local", title: "Local", minWidth: AppColumnWidth.long,
                value: { .text(localText($0)) }
            ) { Text(localText($0)).monospaced() },
            AppTableColumn(
                id: "exposure", title: "Exposure", minWidth: AppColumnWidth.compact,
                value: { .text(primary($0)?.exposure.title) }
            ) { exposureLabel($0) },
            AppTableColumn(
                id: "remote", title: "Remote", minWidth: AppColumnWidth.long,
                value: { .text(remoteLabel($0)) }
            ) { row in
                Text(remoteLabel(row))
                    .monospaced()
                    .foregroundColor(isGroup(row) ? .secondary : .primary)
            },
            AppTableColumn(
                id: "state", title: "State", minWidth: AppColumnWidth.compact,
                value: { .text(stateText($0)) }
            ) { stateLabel($0) },
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
                    .help("Terminate the process owning this row")
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
                Text(group.displayProcess)
                    .font(.caption.weight(.medium))
                Text("\(group.connections.count)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        case .connection(let connection):
            HStack(spacing: 5) {
                if !rules.rules.isEmpty,
                    ConnectionBlockRuleMatcher.matches(connection, rules: rules.rules)
                {
                    Image(systemName: "shield.fill")
                        .font(.caption2)
                        .foregroundColor(AppPalette.warning)
                        .help("Matches a block rule")
                }
                Text(connection.process)
            }
            .padding(.leading, 18)
        }
    }

    @ViewBuilder
    private func rowMenu(_ row: TableRow) -> some View {
        switch row {
        case .group(let group):
            Button(expanded.contains(group.id) ? "Collapse group" : "Expand group") {
                toggle(group.id)
            }
            Button("Copy group") {
                let lines = [group.displayProcess, group.local, group.stateSummary]
                copyToPasteboard(lines.joined(separator: "\t"))
            }
            Divider()
            blockMenu(row)
            Button("Terminate \(group.displayProcess)", role: .destructive) {
                prepareKill(row)
            }
        case .connection(let connection):
            Button("Copy socket") { copyToPasteboard(connection.contextText) }
            Divider()
            blockMenu(row)
            Button("Terminate \(connection.process)", role: .destructive) {
                prepareKill(row)
            }
        }
    }

    private func activate(_ row: TableRow) {
        guard case .group(let group) = row else { return }
        toggle(group.id)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Row helpers

    private func primary(_ row: TableRow) -> OpenConnection? {
        switch row {
        case .group(let group): return group.connections.first
        case .connection(let connection): return connection
        }
    }

    private func isGroup(_ row: TableRow) -> Bool {
        if case .group = row { return true }
        return false
    }

    private func pidLabel(_ row: TableRow) -> String {
        switch row {
        case .group(let group):
            let pids = Array(Set(group.connections.map(\.pid))).sorted()
            if pids.count == 1 { return "\(pids[0])" }
            return "\(pids.prefix(2).map(String.init).joined(separator: ", "))…"
        case .connection(let connection): return "\(connection.pid)"
        }
    }

    /// P3.10: the bundled offline catalogue answers for the process; unknown
    /// names stay "Unknown service" and carry the raw name in the tooltip.
    @ViewBuilder
    private func serviceLabel(_ row: TableRow) -> some View {
        if let connection = primary(row) {
            let description = descriptions.description(forProcess: connection.process)
            Text(description.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundColor(description.source == .unknown ? .secondary : .primary)
                .help("\(description.category) · \(connection.process)")
        } else {
            Text("—")
        }
    }

    private func protoLabel(_ row: TableRow) -> String {
        guard let connection = primary(row) else { return "—" }
        return "\(connection.protocolName) \(connection.transport)"
    }

    @ViewBuilder
    private func exposureLabel(_ row: TableRow) -> some View {
        if let connection = primary(row) {
            let exposure = connection.exposure
            Text(exposure.title)
                .font(.caption2)
                .foregroundColor(
                    exposure.isLANReachable ? AppPalette.warning : .secondary
                )
                .help(exposure.detail)
        } else {
            Text("—")
        }
    }

    private var watchBinding: Binding<Bool> {
        Binding(
            get: { watcher.isWatching },
            set: { enabled in
                if enabled {
                    Task { _ = await MonitorNotifier.shared.requestAuthorization() }
                }
                watcher.setWatching(enabled)
            }
        )
    }

    @ViewBuilder
    private var watcherCard: some View {
        if watcher.isWatching || !watcher.changes.isEmpty {
            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    HStack(spacing: DesignToken.Spacing.small) {
                        SectionLabel(text: "Listener watch")
                        if watcher.isSampling { ProgressView().controlSize(.mini) }
                        Spacer()
                        if let at = watcher.lastSampleAt {
                            Text("Last sampled \(at.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        AppButton(
                            "Sample now", isBusy: watcher.isSampling,
                            isEnabled: !watcher.isSampling
                        ) {
                            Task { await watcher.sampleNow() }
                        }
                        AppButton(
                            "Clear", tone: .quiet, isEnabled: !watcher.changes.isEmpty
                        ) {
                            watcher.clearChanges()
                        }
                    }

                    if let error = watcher.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(AppPalette.danger)
                    } else if watcher.changes.isEmpty {
                        Text("No listener changes yet. Watching samples lsof every 30 s.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(watcher.changes.prefix(6)) { change in
                            HStack(spacing: 6) {
                                Image(
                                    systemName: change.kind == .opened
                                        ? "plus.circle.fill" : "minus.circle.fill"
                                )
                                .font(.caption2)
                                .foregroundColor(
                                    change.kind == .opened
                                        ? AppPalette.warning : AppPalette.muted)
                                Text(change.listener.label)
                                    .font(.caption.monospaced())
                                Text(change.listener.exposure.title)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(
                                    change.at.formatted(date: .omitted, time: .standard)
                                )
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    Text(
                        "One notification per new or closed listener. Loopback sockets are labelled local; everything else is LAN-reachable, never \"public\", because LanFi cannot see your router's port forwarding."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func processName(_ row: TableRow) -> String {
        switch row {
        case .group(let group): return group.displayProcess
        case .connection(let connection): return connection.process
        }
    }

    private func pidValue(_ row: TableRow) -> Int {
        switch row {
        case .group(let group): return group.connections.map(\.pid).min() ?? 0
        case .connection(let connection): return connection.pid
        }
    }

    private func serviceTitle(_ row: TableRow) -> String {
        guard let connection = primary(row) else { return "" }
        return descriptions.description(forProcess: connection.process).title
    }

    private func localText(_ row: TableRow) -> String {
        switch row {
        case .group(let group): return group.local
        case .connection(let connection): return connection.local
        }
    }

    private func stateText(_ row: TableRow) -> String {
        switch row {
        case .group(let group): return group.stateSummary
        case .connection(let connection): return connection.state
        }
    }

    private func remoteLabel(_ row: TableRow) -> String {
        switch row {
        case .group(let group):
            let remote = group.remoteCount
            return remote == 0 ? "—" : String(localized: "\(remote) remote")
        case .connection(let connection): return connection.remote
        }
    }

    @ViewBuilder
    private func stateLabel(_ row: TableRow) -> some View {
        switch row {
        case .group(let group):
            Text(group.stateSummary)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(group.stateSummary)
        case .connection(let connection):
            Text(connection.state)
                .foregroundColor(connection.isListening ? AppPalette.warning : .secondary)
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
        let rows: [OpenConnection]
        let label: String
        switch row {
        case .group(let group):
            rows = group.connections
            label = group.displayProcess
        case .connection(let connection):
            rows = [connection]
            label = "\(connection.process) (\(connection.pid))"
        }
        let pids = Array(Set(rows.map(\.pid))).sorted()
        killTarget = KillTarget(
            pids: pids,
            label: pids.count == 1 ? label : "\(label) — \(pids.count) processes")
        showKillConfirmation = true
    }

    private func terminate(_ target: KillTarget) {
        var failures: [String] = []
        for pid in target.pids {
            let result = ConnectionControlService.terminate(pid: pid)
            if !result.succeeded { failures.append(result.message) }
        }
        if failures.isEmpty {
            notice = String(
                localized: "Sent SIGTERM to \(target.pids.count) process(es).")
        } else {
            errorMessage = failures.joined(separator: "\n")
        }
        Task { await refresh() }
    }

    @ViewBuilder
    private func blockMenu(_ row: TableRow) -> some View {
        if let connection = primary(row) {
            Menu {
                Button("Block application “\(connection.applicationName)”") {
                    add(.application, connection.applicationName)
                }
                Button("Block process “\(connection.process)”") {
                    add(.process, connection.process)
                }
                if let port = connection.remotePort ?? connection.localPort {
                    Button("Block port \(port)") { add(.port, port) }
                }
                if connection.remote != "—" {
                    Button("Block host \(connection.remoteHost)") {
                        add(.remoteHost, connection.remoteHost)
                    }
                }
                Button("Block user “\(connection.user)”") { add(.user, connection.user) }
                Divider()
                Button("Custom rule…") {
                    ruleDraft = BlockRuleDraft(
                        scope: .application, value: connection.applicationName,
                        note: "From \(connection.process) (\(connection.pid))")
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

    private func add(_ scope: BlockRuleScope, _ value: String) {
        let rule = ConnectionBlockRule(scope: scope, value: value)
        rules.add(rule)
        notice = String(localized: "Added rule: \(scope.title) \(value)")
    }

    // MARK: Data

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            connections = try await OpenConnectionsService.fetch(
                includeListeners: includeListeners, includeUDP: includeUDP)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func copy() {
        let text = filtered.map {
            "\($0.process)\t\($0.pid)\t\($0.user)\t\($0.transport)\t\($0.local)\t\($0.remote)\t\($0.state)\t\($0.exposure.title)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum SocketGroupMode: String, CaseIterable, Identifiable {
    case socket
    case process

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socket: return String(localized: "By socket")
        case .process: return String(localized: "By application")
        }
    }
}

/// The rule editor sheet is shared by the Sockets screen and the Rules tab.
struct BlockRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scope: BlockRuleScope
    @State private var value: String
    @State private var note: String
    let onSave: (ConnectionBlockRule) -> Void

    init(draft: BlockRuleDraft, onSave: @escaping (ConnectionBlockRule) -> Void) {
        _scope = State(initialValue: draft.scope)
        _value = State(initialValue: draft.value)
        _note = State(initialValue: draft.note ?? "")
        self.onSave = onSave
    }

    private var trimmed: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            Text("New block rule")
                .font(.title3.weight(.semibold))
            Picker("Match", selection: $scope) {
                ForEach(BlockRuleScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.menu)
            TextField("Value", text: $value)
                .textFieldStyle(.roundedBorder)
            Text(scope.hint)
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add rule") {
                    onSave(
                        ConnectionBlockRule(
                            scope: scope, value: trimmed,
                            note: note.isEmpty ? nil : note))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed.isEmpty)
            }
        }
        .padding(DesignToken.Spacing.card)
        .frame(width: 420)
    }
}
