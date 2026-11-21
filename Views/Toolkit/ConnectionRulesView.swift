import AppKit
import SwiftUI

/// The Rules tab: what LanFi considers blocked and why there is no packet
/// filter behind it.
struct ConnectionRulesView: View {
    @ObservedObject var rules: ConnectionRulesModel
    @State private var editor: BlockRuleDraft?
    @State private var suggestions: [RuleTarget] = []
    @State private var isLoadingSuggestions = false
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack {
                AppButton("Add rule", systemImage: "plus", tone: .primary) {
                    editor = BlockRuleDraft(scope: .application, value: "")
                }
                if !rules.rules.isEmpty {
                    Button("Remove all", role: .destructive) { rules.removeAll() }
                        .buttonStyle(.borderless)
                }
                Spacer()
                if let notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(
                    rules.rules.isEmpty
                        ? String(localized: "No rules")
                        : String(localized: "\(rules.rules.count) rules")
                )
                .font(.caption)
                .foregroundColor(.secondary)
                fileMenu
            }

            AppCard {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    Label("Process-level blocking", systemImage: "hand.raised.fill")
                        .font(.headline)
                    Text(
                        "LanFi has no root helper and installs no packet filter. A rule marks every matching socket in Sockets and Traffic, and you can terminate the processes that own them. macOS will not let LanFi kill processes owned by other users."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !suggestions.isEmpty {
                suggestionsCard
            }

            if rules.rules.isEmpty {
                ToolkitEmptyState(
                    icon: "shield.lefthalf.filled",
                    title: "No block rules",
                    message:
                        "Pick a running process or an installed application, or create one from any socket or process row."
                )
            } else {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                    ForEach(rules.rules) { rule in
                        AppCard {
                            HStack(spacing: DesignToken.Spacing.small) {
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { rules.setEnabled($0, id: rule.id) })
                                )
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                                .labelsHidden()
                                .help(rule.isEnabled ? "Disable this rule" : "Enable this rule")
                                .accessibilityLabel("Enabled")

                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(
                                        rule.isEnabled
                                            ? AppPalette.warning : .secondary.opacity(0.6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.value)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                    HStack(spacing: 5) {
                                        Text(rule.scope.title)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        if !rule.isEnabled {
                                            Text("Disabled")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, DesignToken.Spacing.tight)
                                                .background(
                                                    Color.secondary.opacity(0.14), in: Capsule())
                                        }
                                    }
                                }
                                .opacity(rule.isEnabled ? 1 : 0.6)
                                Spacer()
                                Text(rule.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Button {
                                    editor = BlockRuleDraft(rule: rule)
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help("Edit this rule")
                                .accessibilityLabel("Edit this rule")
                                Button(role: .destructive) {
                                    rules.remove(id: rule.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete this rule")
                                .accessibilityLabel("Delete this rule")
                            }
                        }
                    }
                }
            }
        }
        .appContentPadding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editor) { draft in
            BlockRuleEditorSheet(draft: draft) { rule in
                if draft.ruleID == nil {
                    rules.add(rule)
                } else {
                    rules.update(rule)
                }
                notice = nil
                Task { await refreshSuggestions() }
            }
        }
        .task { await refreshSuggestions() }
        .onChange(of: rules.rules) { _ in Task { await refreshSuggestions() } }
    }

    /// Apps that are talking right now and have no rule yet. One click turns a
    /// row into a rule, which is the whole point of a rules screen: you see
    /// what is active instead of recalling executable names.
    private var suggestionsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.tight) {
                    Label("Active connections without a rule", systemImage: "bolt.horizontal")
                        .font(.headline)
                    if isLoadingSuggestions {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignToken.Spacing.tight) {
                        ForEach(suggestions) { target in
                            Button {
                                rules.add(target.rule)
                            } label: {
                                HStack(spacing: DesignToken.Spacing.tight) {
                                    Image(systemName: "plus.circle")
                                        .font(.caption2.weight(.semibold))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(target.name)
                                            .font(.caption.weight(.medium))
                                        Text(target.detail)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, DesignToken.Spacing.small)
                                .padding(.vertical, DesignToken.Spacing.tight)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                                        .stroke(
                                            Color.secondary.opacity(
                                                DesignToken.Toolbar.strokeOpacity),
                                            lineWidth: DesignToken.Stroke.hairline)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Add a rule for \(target.name)")
                        }
                    }
                }
            }
        }
    }

    /// Moving a rule set to another machine, or keeping a copy before an
    /// experiment, is one JSON file in each direction.
    private var fileMenu: some View {
        Menu {
            Button(String(localized: "Export rules…"), systemImage: "square.and.arrow.up") {
                exportRules()
            }
            .disabled(rules.rules.isEmpty)
            Button(String(localized: "Import rules…"), systemImage: "square.and.arrow.down") {
                importRules()
            }
        } label: {
            AppIconMenuLabel(systemImage: "doc.badge.gearshape")
        }
        .appMenuStyle()
        .help("Rules file")
        .accessibilityLabel("Rules file")
    }

    private func exportRules() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "lanfi-block-rules.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try rules.exportData().write(to: url, options: .atomic)
            notice = String(
                format: String(localized: "Exported %lld rules"), rules.rules.count)
        } catch {
            notice = String(localized: "Could not write the rules file.")
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try rules.importData(Data(contentsOf: url))
            notice = String(
                format: String(localized: "Imported %lld rules (%lld updated)"),
                result.added, result.updated)
            Task { await refreshSuggestions() }
        } catch {
            notice = String(localized: "That file is not a LanFi rules file.")
        }
    }

    private func refreshSuggestions() async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        guard let connections = try? await OpenConnectionsService.fetch(includeListeners: false)
        else {
            suggestions = []
            return
        }
        suggestions = RuleSuggestionBuilder.suggestions(
            connections: connections, rules: rules.rules)
    }
}

struct BlockRuleDraft: Identifiable {
    let id = UUID()
    /// Set when an existing rule is opened for editing. The sheet keeps the
    /// rule's id and creation date, so saving updates instead of duplicating.
    var ruleID: UUID?
    var createdAt: Date?
    var scope: BlockRuleScope
    var value: String
    var note: String?
    var isEnabled = true

    init(scope: BlockRuleScope, value: String, note: String? = nil) {
        self.scope = scope
        self.value = value
        self.note = note
    }

    init(rule: ConnectionBlockRule) {
        ruleID = rule.id
        createdAt = rule.createdAt
        scope = rule.scope
        value = rule.value
        note = rule.note
        isEnabled = rule.isEnabled
    }
}
