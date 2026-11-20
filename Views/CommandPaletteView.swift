import AppKit
import SwiftUI

/// ⌘K palette over every tool, settings page and Wi-Fi workspace panel.
///
/// The entries come from `CommandIndex`, so a new screen is discoverable as
/// soon as it registers a destination; this view only renders and dispatches.
/// Arrow keys move a highlighted row, Return opens it, Escape closes; clicking
/// a row still opens it directly.
struct CommandPaletteView: View {
    let perform: (CommandItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = CommandPaletteSelection()
    @State private var keyMonitor: Any?
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
        .onAppear {
            isSearchFocused = true
            selection.reset(to: results)
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: query) { _ in
            // The result set changed under the cursor; keep the row if it is
            // still there, otherwise highlight the new best match.
            selection.reset(to: results)
        }
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
            Text(verbatim: "↑↓ · return · esc")
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
            ScrollViewReader { proxy in
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
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.bottom, DesignToken.Spacing.small)
                }
                .onChange(of: selection.id) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
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
            Text("↑↓ moves the highlight, Return opens it, Esc closes the palette.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: CommandItem) -> some View {
        let isSelected = selection.id == item.id
        return Button {
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
                if isSelected {
                    Text("↩")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, DesignToken.Spacing.medium)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isSelected ? Theme.Surface.selectionFill : Color.clear)
                    .padding(.horizontal, DesignToken.Spacing.tight)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.subtitle.isEmpty ? item.title : item.subtitle)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
        .onHover { hovering in
            // Hovering previews the keyboard target, so the mouse and the
            // keyboard never disagree about what Return will open.
            if hovering { selection = CommandPaletteSelection(id: item.id) }
        }
    }

    private func icon(for item: CommandItem) -> String {
        switch item.destination {
        case .tool(let tool): return tool.icon
        case .settings(let section): return section.icon
        case .wifiTab: return "rectangle.split.3x1"
        }
    }

    // MARK: - Keyboard

    /// A local monitor is used because the search field owns the arrow keys:
    /// SwiftUI would otherwise move the caret instead of the highlight.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard
                event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            else { return event }
            switch event.keyCode {
            case 126:  // ↑
                move(-1)
                return nil
            case 125:  // ↓
                move(1)
                return nil
            case 36, 76:  // Return, keypad Enter
                openSelected()
                return nil
            case 53:  // Esc
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func move(_ step: Int) {
        selection.move(by: step, in: results)
    }

    private func openSelected() {
        open(selection.item(in: results) ?? results.first)
    }

    private func open(_ item: CommandItem?) {
        guard let item else { return }
        removeKeyMonitor()
        perform(item)
        dismiss()
    }
}
