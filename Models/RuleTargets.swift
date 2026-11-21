import AppKit
import Foundation

/// One thing a block rule can be created from instead of typing a value by
/// hand: a running process, an installed application, or a process that holds a
/// socket right now.
///
/// The catalog is plain data. AppKit lookups and the `/Applications` scan live
/// in `RuleTargetCatalog.discover()`, so the pieces that decide *what a rule
/// says* stay testable without a running app or a disk.
struct RuleTarget: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case running
        case application
        case socket
    }

    let id: String
    let name: String
    /// Secondary line: PID, bundle identifier or the app's location.
    let detail: String
    let scope: BlockRuleScope
    let value: String
    let kind: Kind

    var rule: ConnectionBlockRule {
        ConnectionBlockRule(scope: scope, value: value)
    }
}

enum RuleTargetCatalog {
    /// A running process as AppKit describes it, reduced to what a rule needs.
    struct RunningProcess: Hashable {
        let name: String
        let pid: Int
        let bundleIdentifier: String?
        /// Executable name, used for processes that own no application bundle.
        let executable: String
    }

    /// An `*.app` on disk.
    struct ApplicationBundle: Hashable {
        let name: String
        let path: String
        let bundleIdentifier: String?
    }

    /// Builds the picker's list: installed applications, merged with the
    /// processes that are running now.
    ///
    /// A running app wins over its bundle on disk so the row can show its PID;
    /// helpers and daemons that own no bundle are matched by executable name.
    static func targets(
        running: [RunningProcess], applications: [ApplicationBundle]
    ) -> [RuleTarget] {
        var byName: [String: RuleTarget] = [:]
        var order: [String] = []

        for app in applications {
            let key = app.name.lowercased()
            guard byName[key] == nil else { continue }
            order.append(key)
            byName[key] = RuleTarget(
                id: "app|\(app.path)",
                name: app.name,
                detail: app.bundleIdentifier ?? app.path,
                scope: .application,
                value: app.name,
                kind: .application)
        }

        for process in running {
            let key = process.name.lowercased()
            let detail =
                process.bundleIdentifier.map { "PID \(process.pid) · \($0)" }
                ?? "PID \(process.pid) · \(process.executable)"
            if let existing = byName[key] {
                byName[key] = RuleTarget(
                    id: existing.id,
                    name: existing.name,
                    detail: detail,
                    scope: existing.scope,
                    value: existing.value,
                    kind: .running)
                continue
            }
            order.append(key)
            // A process without a bundle is matched by executable name, which
            // is what lsof reports; a bundled app matches its display name.
            let isApp = process.bundleIdentifier != nil
            byName[key] = RuleTarget(
                id: "pid|\(process.pid)",
                name: process.name,
                detail: detail,
                scope: isApp ? .application : .process,
                value: isApp ? process.name : process.executable,
                kind: .running)
        }

        return order.compactMap { byName[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Running applications plus the helpers that appear in a socket list but
    /// own no bundle of their own.
    @MainActor
    static func runningProcesses(
        connections: [OpenConnection] = []
    ) -> [RunningProcess] {
        var processes: [String: RunningProcess] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard !app.isTerminated, let name = app.localizedName, !name.isEmpty
            else { continue }
            let executable =
                app.executableURL?.lastPathComponent ?? app.bundleURL?.lastPathComponent ?? name
            processes["app|\(app.processIdentifier)"] = RunningProcess(
                name: name,
                pid: Int(app.processIdentifier),
                bundleIdentifier: app.bundleIdentifier,
                executable: executable)
        }
        // Helper processes (renderers, XPC services) never appear as running
        // applications, but they own sockets and are what the user sees in the
        // Sockets tab.
        for connection in connections {
            let key = "pid|\(connection.pid)"
            guard processes[key] == nil,
                !processes.values.contains(where: { $0.pid == connection.pid })
            else { continue }
            processes[key] = RunningProcess(
                name: connection.process,
                pid: connection.pid,
                bundleIdentifier: nil,
                executable: connection.process)
        }
        return Array(processes.values)
    }

    /// Applications in the usual install locations, read from their Info.plist
    /// rather than from the folder name.
    static func installedApplications(
        directories: [URL] = defaultApplicationDirectories()
    ) -> [ApplicationBundle] {
        let manager = FileManager.default
        var bundles: [ApplicationBundle] = []
        var seen = Set<String>()
        for directory in directories {
            let contents =
                (try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles])) ?? []
            for url in contents where url.pathExtension == "app" {
                let name = displayName(ofBundleAt: url) ?? url.deletingPathExtension().lastPathComponent
                let identifier = bundleIdentifier(ofBundleAt: url)
                let key = "\(url.standardizedFileURL.path)"
                guard seen.insert(key).inserted else { continue }
                bundles.append(
                    ApplicationBundle(
                        name: name, path: url.path, bundleIdentifier: identifier))
            }
        }
        return bundles
    }

    static func defaultApplicationDirectories() -> [URL] {
        var directories = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        if let home = FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first {
            directories.append(home)
        }
        return directories
    }

    static func displayName(ofBundleAt url: URL) -> String? {
        guard
            let bundle = Bundle(url: url),
            let name =
                (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String),
            !name.isEmpty
        else { return nil }
        return name
    }

    static func bundleIdentifier(ofBundleAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    /// Everything the picker can offer, discovered once when the sheet opens.
    @MainActor
    static func discover(connections: [OpenConnection] = []) -> [RuleTarget] {
        targets(
            running: runningProcesses(connections: connections),
            applications: installedApplications())
    }
}

// MARK: - Suggestions

/// Apps that hold sockets right now and are not covered by any rule yet: the
/// "one click away" list on the Rules tab.
enum RuleSuggestionBuilder {
    static func suggestions(
        connections: [OpenConnection], rules: [ConnectionBlockRule]
    ) -> [RuleTarget] {
        var counts: [String: (name: String, count: Int)] = [:]
        for connection in connections {
            guard !connection.isListener else { continue }
            let name = connection.applicationName
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            let current = counts[key]?.count ?? 0
            counts[key] = (name, current + 1)
        }
        let covered = Set(
            rules.filter { $0.isEnabled && $0.scope == .application }
                .map { $0.value.lowercased() })
        var ranked: [(count: Int, target: RuleTarget)] = []
        for (key, value) in counts where !covered.contains(key) {
            let detail =
                value.count == 1
                ? String(localized: "1 connection")
                : String(localized: "\(value.count) connections")
            let target = RuleTarget(
                id: "suggest|\(key)",
                name: value.name,
                detail: detail,
                scope: .application,
                value: value.name,
                kind: .socket)
            ranked.append((value.count, target))
        }
        ranked.sort { left, right in
            if left.count != right.count { return left.count > right.count }
            return left.target.name.localizedStandardCompare(right.target.name) == .orderedAscending
        }
        return ranked.map(\.target)
    }
}
