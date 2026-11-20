import Foundation

/// Where a command palette entry takes the user.
enum CommandDestination: Equatable {
    case tool(ToolboxTool)
    case settings(SettingsSection)
    /// A panel of the Wi-Fi workspace, addressed by its bottom-tab index.
    case wifiTab(Int)
}

/// One indexed action behind ⌘K.
struct CommandItem: Identifiable, Equatable {
    let id: String
    let title: String
    /// A short line under the title; empty when the title says everything.
    let subtitle: String
    let category: String
    /// Extra words a user might type instead of the title.
    let keywords: [String]
    let destination: CommandDestination
}

/// The palette's searchable index.
///
/// The index is declarative: every sidebar tool, every settings page and every
/// Wi-Fi workspace panel is registered here once, so a new screen shows up in
/// ⌘K without touching the palette view. Ranking is deliberately simple and
/// unit-tested: an exact title beats a title prefix, which beats a title
/// substring, then a keyword, then the subtitle and finally the category.
enum CommandIndex {
    static let all: [CommandItem] = toolItems + settingsItems + workspaceItems

    /// Ranked matches, best first. An empty query returns nothing: the palette
    /// lists destinations only once the user starts typing.
    static func results(for query: String, limit: Int = 12) -> [CommandItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return all.compactMap { item -> (item: CommandItem, score: Int)? in
            guard let score = rank(item, query: trimmed) else { return nil }
            return (item, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.item.title.count != rhs.item.title.count {
                return lhs.item.title.count < rhs.item.title.count
            }
            return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
        }
        .prefix(max(0, limit))
        .map(\.item)
    }

    /// A lower score is a better match; nil means the item does not match.
    static func rank(_ item: CommandItem, query: String) -> Int? {
        let needle = query.lowercased()
        let title = item.title.lowercased()
        if title == needle { return 0 }
        if title.hasPrefix(needle) { return 1 }
        if title.contains(needle) { return 2 }
        if item.keywords.contains(where: { $0.lowercased().contains(needle) }) { return 3 }
        if item.subtitle.lowercased().contains(needle) { return 4 }
        if item.category.lowercased().contains(needle) { return 5 }
        return nil
    }

    // MARK: - Entries

    private static var toolItems: [CommandItem] {
        ToolboxTool.allCases.filter { $0.isAvailable && $0.showsInSidebar }.map { tool in
            CommandItem(
                id: "tool.\(tool.rawValue)",
                title: tool.title,
                subtitle: tool.plannedDetail,
                category: tool.section.title,
                keywords: tool.mcpTools,
                destination: .tool(tool))
        }
    }

    private static var settingsItems: [CommandItem] {
        SettingsSection.allCases.map { section in
            CommandItem(
                id: "settings.\(section.rawValue)",
                title: section.title,
                subtitle: String(localized: "Settings"),
                category: String(localized: "Settings"),
                keywords: settingsKeywords[section] ?? [],
                destination: .settings(section))
        }
    }

    /// Panels of the Wi-Fi workspace, with the bottom-tab index each one uses.
    private static var workspaceItems: [CommandItem] {
        [
            (0, String(localized: "Insights"), "sparkles"),
            (1, String(localized: "Profile"), "square.stack.3d.up"),
            (3, String(localized: "Raw Data"), "list.bullet.rectangle"),
            (4, String(localized: "Spectrum"), "waveform.path.ecg"),
            (5, String(localized: "History"), "clock.arrow.circlepath"),
            (7, String(localized: "Capture"), "record.circle"),
            (8, String(localized: "Monitor"), "waveform.path.ecg.rectangle"),
            (9, String(localized: "All Bands"), "rectangle.split.3x1"),
        ].map { tab, title, _ in
            CommandItem(
                id: "workspace.\(tab)",
                title: title,
                subtitle: String(localized: "Wi-Fi workspace"),
                category: String(localized: "Wi-Fi workspace"),
                keywords: [],
                destination: .wifiTab(tab))
        }
    }

    /// Words that are not in a page's title but describe what it holds, so
    /// "anonymous statistics" finds Privacy and "resolver benchmark" finds
    /// Diagnostics.
    private static let settingsKeywords: [SettingsSection: [String]] = [
        .general: ["appearance", "density", "language", "updates", "launch at login"],
        .alerts: ["notifications", "threshold", "quiet hours"],
        .wifi: ["scan interval", "interface", "location", "rssi"],
        .vendors: ["oui", "vendor database", "manufacturer", "oui update"],
        .colors: ["colour rules", "tint", "palette"],
        .columns: ["expression columns", "custom columns", "table columns"],
        .diagnostics: ["resolver benchmark", "dns benchmark", "export bundle"],
        .hardware: ["spectrum", "external adapter", "radio"],
        .automation: ["shortcuts", "url scheme", "intents", "deep link"],
        .controllers: ["unifi", "access points", "wireless controller"],
        .mcp: ["mcp server", "agents", "automation api"],
        .privacy: ["anonymous statistics", "telemetry", "crash reports", "redaction"],
        .toolkit: ["default target", "analysis target", "toolkit settings"],
    ]
}
