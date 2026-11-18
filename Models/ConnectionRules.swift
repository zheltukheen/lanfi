import AppKit
import Combine
import Foundation

// MARK: - Block rules

/// What a LanFi block rule matches.
///
/// LanFi has no kernel extension or root helper: a rule marks matching sockets
/// and lets the user terminate their owning processes. It is deliberately
/// called a block rule, not a packet filter, so the screen never claims to do
/// something macOS has not actually enforced.
enum BlockRuleScope: String, CaseIterable, Identifiable, Codable, Equatable {
    case application
    case process
    case pid
    case remoteHost
    case port
    case user

    var id: String { rawValue }

    var title: String {
        switch self {
        case .application: return String(localized: "Application")
        case .process: return String(localized: "Process name")
        case .pid: return String(localized: "Process ID")
        case .remoteHost: return String(localized: "Remote host")
        case .port: return String(localized: "Local or remote port")
        case .user: return String(localized: "User")
        }
    }

    var hint: String {
        switch self {
        case .application: return String(localized: "Matches the app name owning the socket.")
        case .process: return String(localized: "Matches the executable name, including helpers.")
        case .pid: return String(localized: "Matches one process instance.")
        case .remoteHost: return String(localized: "Matches the remote address.")
        case .port: return String(localized: "Matches a port on either endpoint.")
        case .user: return String(localized: "Matches the socket owner.")
        }
    }
}

struct ConnectionBlockRule: Identifiable, Codable, Equatable {
    let id: UUID
    var scope: BlockRuleScope
    var value: String
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(), scope: BlockRuleScope, value: String, note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.value = value
        self.note = note
        self.createdAt = createdAt
    }

    var displayValue: String { value.isEmpty ? "—" : value }

    func matches(_ connection: OpenConnection) -> Bool {
        switch scope {
        case .application:
            return connection.applicationName.compare(value, options: .caseInsensitive)
                == .orderedSame
        case .process:
            return connection.process.compare(value, options: .caseInsensitive) == .orderedSame
        case .pid:
            return String(connection.pid) == value
        case .remoteHost:
            return connection.remoteHost.compare(value, options: .caseInsensitive)
                == .orderedSame
        case .port:
            return connection.localPort == value || connection.remotePort == value
        case .user:
            return connection.user.compare(value, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Rules that a per-process traffic row can satisfy (nettop exposes no
    /// endpoints, so host and port rules cannot apply there).
    func matches(process: String, pid: Int) -> Bool {
        switch scope {
        case .application:
            let app = NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? process
            return app.compare(value, options: .caseInsensitive) == .orderedSame
        case .process:
            return process.compare(value, options: .caseInsensitive) == .orderedSame
        case .pid:
            return String(pid) == value
        case .remoteHost, .port, .user:
            return false
        }
    }
}

enum ConnectionBlockRuleMatcher {
    static func matches(_ connection: OpenConnection, rules: [ConnectionBlockRule]) -> Bool {
        rules.contains { $0.matches(connection) }
    }

    static func matches(
        process: String, pid: Int, rules: [ConnectionBlockRule]
    ) -> Bool {
        rules.contains { $0.matches(process: process, pid: pid) }
    }

    static func matching(
        _ connections: [OpenConnection], rules: [ConnectionBlockRule]
    ) -> [OpenConnection] {
        connections.filter { matches($0, rules: rules) }
    }
}

/// Persists rules in `~/Library/Application Support/LanFi/block-rules.json`.
final class ConnectionBlockRuleStore {
    private let fileURL: URL

    init(directory: URL? = nil) {
        let base =
            directory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0].appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("block-rules.json")
    }

    func load() -> [ConnectionBlockRule] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([ConnectionBlockRule].self, from: data)) ?? []
    }

    func save(_ rules: [ConnectionBlockRule]) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Socket grouping

/// One local socket with every connection that shares it. `lsof` reports each
/// established session separately, so this is how a busy listener collapses
/// into one expandable row.
struct ConnectionSocketGroup: Identifiable, Equatable {
    let id: String
    let local: String
    /// Application name when the group spans several helper processes.
    var title: String? = nil
    let connections: [OpenConnection]

    var processes: [String] {
        Array(Set(connections.map(\.process))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var displayProcess: String { title ?? processes.joined(separator: ", ") }

    var listeningCount: Int { connections.filter(\.isListening).count }

    var stateSummary: String {
        let states = Array(Set(connections.map(\.state))).sorted()
        return states.joined(separator: ", ")
    }

    var remoteCount: Int {
        Set(connections.map(\.remote).filter { $0 != "—" }).count
    }
}

enum ConnectionGrouping {
    static func bySocket(_ connections: [OpenConnection]) -> [ConnectionSocketGroup] {
        Dictionary(grouping: connections, by: \.local)
            .map { local, rows in
                ConnectionSocketGroup(
                    id: local,
                    local: local,
                    connections: rows.sorted {
                        $0.pid == $1.pid
                            ? $0.remote.localizedStandardCompare($1.remote) == .orderedAscending
                            : $0.pid < $1.pid
                    })
            }
            .sorted {
                $0.connections.count == $1.connections.count
                    ? $0.local.localizedStandardCompare($1.local) == .orderedAscending
                    : $0.connections.count > $1.connections.count
            }
    }

    /// Groups by the owning application rather than the executable, so helpers,
    /// renderers and helper XPC processes of one app share a row instead of
    /// appearing as several "applications" in the list.
    static func byApplication(
        _ connections: [OpenConnection], appName: (Int) -> String?
    ) -> [ConnectionSocketGroup] {
        Dictionary(grouping: connections) { appName($0.pid) ?? $0.process }
            .map { name, rows in
                ConnectionSocketGroup(
                    id: "app|\(name)",
                    local: rows.first?.local ?? "—",
                    title: name,
                    connections: rows.sorted {
                        $0.local.localizedStandardCompare($1.local) == .orderedAscending
                    })
            }
            .sorted {
                let left = $0.connections.count
                let right = $1.connections.count
                return left == right
                    ? $0.displayProcess.localizedStandardCompare($1.displayProcess)
                        == .orderedAscending
                    : left > right
            }
    }

    static func byProcess(_ connections: [OpenConnection]) -> [ConnectionSocketGroup] {
        Dictionary(grouping: connections, by: { "\($0.process)|\($0.pid)" })
            .map { key, rows in
                ConnectionSocketGroup(
                    id: key,
                    local: rows.first?.local ?? "—",
                    connections: rows.sorted {
                        $0.local.localizedStandardCompare($1.local) == .orderedAscending
                    })
            }
            .sorted {
                let left = $0.connections.first
                let right = $1.connections.first
                return (left?.process ?? "").localizedStandardCompare(right?.process ?? "")
                    == .orderedAscending
            }
    }
}

// MARK: - Traffic grouping

struct ProcessTrafficGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let rows: [ProcessTrafficDelta]

    var receivedBytesPerSecond: Double {
        rows.reduce(0) { $0 + $1.receivedBytesPerSecond }
    }
    var sentBytesPerSecond: Double {
        rows.reduce(0) { $0 + $1.sentBytesPerSecond }
    }
    var totalBytes: UInt64 { rows.reduce(0) { $0 + $1.totalBytes } }
}

enum TrafficGrouping {
    /// App names collapse helpers under the same bundle display name.
    static func byApplication(
        _ rows: [ProcessTrafficDelta], appName: (Int) -> String?
    ) -> [ProcessTrafficGroup] {
        Dictionary(grouping: rows) { appName($0.pid) ?? $0.process }
            .map { name, members in
                ProcessTrafficGroup(
                    id: "app|\(name)",
                    name: name,
                    rows: members.sorted {
                        $0.totalBytesPerSecond > $1.totalBytesPerSecond
                    })
            }
            .sorted {
                $0.receivedBytesPerSecond + $0.sentBytesPerSecond
                    > $1.receivedBytesPerSecond + $1.sentBytesPerSecond
            }
    }

    /// Process names keep helpers separate while still grouping multiple PIDs.
    static func byProcess(_ rows: [ProcessTrafficDelta]) -> [ProcessTrafficGroup] {
        Dictionary(grouping: rows, by: \.process)
            .map { name, members in
                ProcessTrafficGroup(
                    id: "process|\(name)",
                    name: name,
                    rows: members.sorted { $0.pid < $1.pid })
            }
            .sorted {
                $0.receivedBytesPerSecond + $0.sentBytesPerSecond
                    > $1.receivedBytesPerSecond + $1.sentBytesPerSecond
            }
    }
}

// MARK: - Observable rule list

final class ConnectionRulesModel: ObservableObject {
    @Published private(set) var rules: [ConnectionBlockRule] = []
    private let store: ConnectionBlockRuleStore

    init(store: ConnectionBlockRuleStore = ConnectionBlockRuleStore()) {
        self.store = store
        rules = store.load()
    }

    func add(_ rule: ConnectionBlockRule) {
        guard !rules.contains(where: { $0.scope == rule.scope && $0.value == rule.value })
        else { return }
        rules.append(rule)
        persist()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        persist()
    }

    func removeAll() {
        rules = []
        persist()
    }

    private func persist() { store.save(rules) }
}

// MARK: - Endpoint helpers

extension OpenConnection {
    /// Bundle display name of the owning app, falling back to the executable
    /// name for daemons and helpers.
    var applicationName: String {
        NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName ?? process
    }

    /// Port of an `lsof` endpoint such as `10.0.0.2:52211`, `[::1]:443` or
    /// `*:22`. Returns nil for the `—` placeholder.
    var localPort: String? { Self.port(of: local) }
    var remotePort: String? { Self.port(of: remote) }

    static func port(of endpoint: String) -> String? {
        guard endpoint != "—", let colon = endpoint.lastIndex(of: ":") else { return nil }
        let port = endpoint[endpoint.index(after: colon)...]
        return port.isEmpty || port == "*" ? nil : String(port)
    }
}
