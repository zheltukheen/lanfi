import SwiftUI

/// The Rules tab: what LanFi considers blocked and why there is no packet
/// filter behind it.
struct ConnectionRulesView: View {
    @ObservedObject var rules: ConnectionRulesModel
    @State private var editor: BlockRuleDraft?

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

            if rules.rules.isEmpty {
                ToolkitEmptyState(
                    icon: "shield.lefthalf.filled",
                    title: "No block rules",
                    message:
                        "Create one from any socket or process row, or add one here for an application, process, port, host or user."
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
            }
        }
    }
}

struct BlockRuleDraft: Identifiable {
    let id = UUID()
    var scope: BlockRuleScope
    var value: String
    var note: String?
}
