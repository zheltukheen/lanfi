import SwiftUI

/// The Rules tab: what LanFi considers blocked and why there is no packet
/// filter behind it.
struct ConnectionRulesView: View {
    @ObservedObject var rules: ConnectionRulesModel
    @State private var editor: BlockRuleDraft?
    @State private var suggestions: [RuleTarget] = []
    @State private var isLoadingSuggestions = false

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
                Text(
                    rules.rules.isEmpty
                        ? String(localized: "No rules")
                        : String(localized: "\(rules.rules.count) rules")
                )
                .font(.caption)
                .foregroundColor(.secondary)
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
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(AppPalette.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.value)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                    Text(rule.scope.title)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(rule.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Button(role: .destructive) {
                                    rules.remove(id: rule.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Delete this rule")
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
                rules.add(rule)
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
    var scope: BlockRuleScope
    var value: String
    var note: String?
}
