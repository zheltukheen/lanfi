import Foundation

/// P1.8: one row from `lsof -nP -iTCP`, parsed without shell interpretation.
struct OpenConnection: Identifiable, Equatable {
    let id: String
    let process: String
    let pid: Int
    let user: String
    let protocolName: String
    /// `TCP` or `UDP`, from lsof's NODE column.
    let transport: String
    let local: String
    let remote: String
    let state: String

    var isListening: Bool { state == "LISTEN" }
    var isUDP: Bool { transport == "UDP" }
    /// A TCP listener or any UDP socket answers clients on its local endpoint.
    var isListener: Bool { isListening || isUDP }
    /// What the local endpoint exposes: loopback only or reachable from the LAN.
    var exposure: SocketExposure { SocketExposureClassifier.classify(local: local) }

    /// One tab-separated line, used by copy actions and context menus.
    var contextText: String {
        [process, String(pid), user, protocolName, local, remote, state]
            .joined(separator: "\t")
    }
    var remoteHost: String {
        guard let colon = remote.lastIndex(of: ":") else { return remote }
        return String(remote[..<colon])
    }
}

enum OpenConnectionsParser {
    /// Parses the default `lsof` column layout:
    /// COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME.
    static func parse(_ output: String) -> [OpenConnection] {
        var result: [OpenConnection] = []
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let columns = line.split(
                maxSplits: 8, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard columns.count >= 9,
                let pid = Int(columns[1])
            else { continue }
            let process = String(columns[0])
            let user = String(columns[2])
            let type = String(columns[4])
            let rawName = String(columns[8])

            var name = rawName
            var state = ""
            if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
                state = String(name[name.index(after: open)..<name.index(before: name.endIndex)])
                name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            }
            let endpoints = name.components(separatedBy: "->")
            let local = endpoints.first ?? name
            let remote = endpoints.count > 1 ? endpoints[1] : ""
            guard type.contains("IPv") else { continue }
            let transport = String(columns[7]).uppercased()
            result.append(
                OpenConnection(
                    id: "\(pid)|\(transport)|\(local)|\(remote)|\(state)",
                    process: process,
                    pid: pid,
                    user: user,
                    protocolName: type,
                    transport: transport,
                    local: local,
                    remote: remote.isEmpty ? "—" : remote,
                    state: state.isEmpty ? "—" : state))
        }
        return result.sorted {
            if $0.process != $1.process {
                return $0.process.localizedStandardCompare($1.process) == .orderedAscending
            }
            return $0.pid < $1.pid
        }
    }

    /// Groups the list by process for the summary cards.
    static func byProcess(_ connections: [OpenConnection]) -> [(process: String, count: Int)] {
        var counts: [String: Int] = [:]
        for connection in connections {
            counts[connection.process, default: 0] += 1
        }
        return counts.map { (process: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.process.localizedStandardCompare(rhs.process) == .orderedAscending
            }
    }
}

/// Where a listening socket can be reached from.
///
/// LanFi deliberately says "LAN-reachable", not "public": without a router
/// table or a packet filter it cannot know whether the port is forwarded.
enum SocketExposure: String, CaseIterable, Equatable, Sendable {
    case loopback
    case allInterfaces
    case specificAddress
    case unknown

    var title: String {
        switch self {
        case .loopback: return String(localized: "Local only")
        case .allInterfaces: return String(localized: "All interfaces")
        case .specificAddress: return String(localized: "LAN-reachable")
        case .unknown: return String(localized: "Unknown")
        }
    }

    var detail: String {
        switch self {
        case .loopback: return String(localized: "Bound to loopback; other devices cannot connect.")
        case .allInterfaces: return String(localized: "Answers on every interface, including the LAN.")
        case .specificAddress: return String(localized: "Bound to one address on this Mac.")
        case .unknown: return String(localized: "The local endpoint could not be parsed.")
        }
    }

    var isLANReachable: Bool { self == .allInterfaces || self == .specificAddress }
}

enum SocketExposureClassifier {
    /// Classifies `lsof`'s local endpoint (`*:5353`, `127.0.0.1:5000`,
    /// `[::1]:80`, `192.168.1.4:8000`).
    static func classify(local: String) -> SocketExposure {
        guard let host = host(of: local) else { return .unknown }
        if host == "*" || host == "0.0.0.0" || host == "::" { return .allInterfaces }
        if host == "localhost" || host == "::1" || host.hasPrefix("127.") { return .loopback }
        return .specificAddress
    }

    /// Splits the host from `host:port`, `[v6]:port` and the wildcard `*:port`.
    static func host(of local: String) -> String? {
        guard let colon = local.lastIndex(of: ":") else { return nil }
        var host = String(local[..<colon])
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        return host.isEmpty ? nil : host
    }
}

enum OpenConnectionsService {
    /// Read-only `lsof`; no shell, no network requests of our own. Some rows
    /// for other users need root, so the list is honest about being partial.
    ///
    /// The TCP pass stays the fast default; `includeUDP` adds the UDP sockets
    /// that can answer clients without ever appearing in a TCP listener list.
    static func fetch(includeListeners: Bool, includeUDP: Bool = false)
        async throws -> [OpenConnection]
    {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            var arguments = ["-nP", "-iTCP"]
            if !includeListeners {
                arguments.append("-sTCP:ESTABLISHED")
            }
            if includeUDP {
                arguments.append("-iUDP")
            }
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            return OpenConnectionsParser.parse(output)
        }.value
    }
}
