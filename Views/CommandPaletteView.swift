import AppKit
import SwiftUI

/// ⌘K palette over every tool, settings page and Wi-Fi workspace panel.
///
/// The entries come from `CommandIndex`, so a new screen is discoverable as
/// soon as it registers a destination; this view only renders and dispatches.
struct CommandPaletteView: View {
    let perform: (CommandItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [CommandItem] {
        CommandIndex.results(for: query)
    }

    private var groups: [(category: String, items: [CommandItem])] {
        var order: [String] = []
        var byCategory: [String: [CommandItem]] = [:]
        for item in results {
            if byCategory[item.category] == nil { order.append(item.category) }
            byCategory[item.category, default: []].append(item)
        }
        return order.map { ($0, byCategory[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .frame(width: 560, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isSearchFocused = true }
        .onExitCommand { dismiss() }
    }

    private var searchField: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search tools, settings and screens", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .onSubmit { open(results.first) }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
            Text("esc")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, DesignToken.Spacing.medium)
        .padding(.vertical, DesignToken.Spacing.compact)
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            placeholder
        } else if results.isEmpty {
            VStack(spacing: DesignToken.Spacing.small) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 26))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("No matches")
                    .font(.headline)
                Text("Try a tool name, a setting or a Wi-Fi panel.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups, id: \.category) { group in
                        Text(group.category.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, DesignToken.Spacing.medium)
                            .padding(.top, DesignToken.Spacing.small)
                            .padding(.bottom, 2)
                        ForEach(group.items) { item in
                            row(item)
                        }
                    }
                }
                .padding(.bottom, DesignToken.Spacing.small)
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: DesignToken.Spacing.small) {
            Image(systemName: "command")
                .font(.system(size: 26))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Type a tool, setting or panel name")
                .font(.headline)
            Text("Return opens the best match. Esc closes the palette.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: CommandItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: DesignToken.Spacing.small) {
                Image(systemName: icon(for: item))
                    .frame(width: 18)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13))
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DesignToken.Spacing.small)
            }
            .padding(.horizontal, DesignToken.Spacing.medium)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.subtitle.isEmpty ? item.title : item.subtitle)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
    }

    private func icon(for item: CommandItem) -> String {
        switch item.destination {
        case .tool(let tool): return tool.icon
        case .settings(let section): return section.icon
        case .wifiTab: return "rectangle.split.3x1"
        }
    }

    private func open(_ item: CommandItem?) {
        guard let item else { return }
        perform(item)
        dismiss()
    }
}
