import Foundation

/// P3.6 — which host names an app talked to. Only the host is kept: no path,
/// no query string, no payload, no cookie. Names come from a HAR the user
/// opened in LanFi (`serverIPAddress` → `host`) or from cached reverse DNS of
/// the remote endpoints in `lsof`, never from packet contents.
struct DomainObservation: Codable, Equatable, Sendable {
    var hits: Int
    var lastSeen: Date
}

struct AppDomainAttribution: Codable, Equatable, Sendable {
    /// app name -> host -> observation.
    var apps: [String: [String: DomainObservation]] = [:]
    var updatedAt: Date?

    static let empty = AppDomainAttribution()
    static let retentionDays = 7

    mutating func record(app: String, domain: String, at date: Date = Date()) {
        guard let domain = DomainAttributionRules.normalize(domain) else { return }
        var observations = apps[app] ?? [:]
        var observation = observations[domain] ?? DomainObservation(hits: 0, lastSeen: date)
        observation.hits += 1
        observation.lastSeen = date
        observations[domain] = observation
        apps[app] = observations
        updatedAt = date
    }

    func topDomains(forApp app: String, limit: Int = 3) -> [(domain: String, hits: Int)] {
        (apps[app] ?? [:])
            .sorted { left, right in
                if left.value.hits != right.value.hits { return left.value.hits > right.value.hits }
                return left.value.lastSeen > right.value.lastSeen
            }
            .prefix(max(0, limit))
            .map { (domain: $0.key, hits: $0.value.hits) }
    }

    /// One row per app, with its strongest domain, for the compact card.
    func appSummaries(limit: Int = 8) -> [(app: String, domain: String, hits: Int)] {
        apps.compactMap { app, domains in
            guard
                let best = domains.max(by: { left, right in
                    if left.value.hits != right.value.hits { return left.value.hits < right.value.hits }
                    return left.value.lastSeen < right.value.lastSeen
                })
            else { return nil }
            return (app: app, domain: best.key, hits: best.value.hits)
        }
        .sorted { $0.hits > $1.hits }
        .prefix(max(0, limit))
        .map { $0 }
    }

    mutating func prune(before date: Date) {
        for (app, domains) in apps {
            let kept = domains.filter { $0.value.lastSeen >= date }
            if kept.isEmpty {
                apps.removeValue(forKey: app)
            } else {
                apps[app] = kept
            }
        }
    }

    func csv() -> String {
        var lines = ["app,domain,hits,last_seen"]
        for app in apps.keys.sorted() {
            for (domain, observation) in (apps[app] ?? [:]).sorted(by: { $0.key < $1.key }) {
                lines.append(
                    "\(Self.escape(app)),\(Self.escape(domain)),\(observation.hits),\(ISO8601DateFormatter().string(from: observation.lastSeen))"
                )
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

enum DomainAttributionRules {
    static let ownProcessName = "lanfi"

    /// Host only: lowercased, no port, no brackets, no trailing dot, no path.
    /// IP literals are rejected because they are not a domain and the screen
    /// already shows the endpoint.
    static func normalize(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") { value = String(value[..<slash]) }
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            value = String(value[value.index(after: value.startIndex)..<close])
        } else if let colon = value.lastIndex(of: ":"), value.filter({ $0 == ":" }).count == 1 {
            // `host:port`; a bare IPv6 literal has more than one colon and is
            // rejected below.
            value = String(value[..<colon])
        }
        if value.hasSuffix(".") { value.removeLast() }
        guard !value.isEmpty, value.count <= 253 else { return nil }
        guard value.contains("."), !value.contains(" ") else { return nil }
        guard !isIPLiteral(value) else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-._")
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        guard value.split(separator: ".").allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else {
            return nil
        }
        return value
    }

    static func isIPLiteral(_ value: String) -> Bool {
        if value.contains(":") { return true }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// `serverIPAddress` → host from a HAR. The HAR is user-provided; only the
    /// host is stored, and only as an attribution hint for later connections.
    static func httpDomainIndex(from traffic: HARTraffic) -> [String: String] {
        var index: [String: String] = [:]
        for entry in traffic.entries {
            guard let ip = entry.serverIP?.trimmingCharacters(in: .whitespacesAndNewlines),
                !ip.isEmpty,
                let domain = normalize(entry.host)
            else { continue }
            index[ip] = domain
        }
        return index
    }

    /// `1.2.3.4:443`, `[2001:db8::1]:443` and bare `1.2.3.4` → the address.
    static func remoteAddress(_ endpoint: String) -> String? {
        var value = endpoint.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != "*" else { return nil }
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            value = String(value[value.index(after: value.startIndex)..<close])
        } else if value.filter({ $0 == ":" }).count == 1, let colon = value.lastIndex(of: ":") {
            value = String(value[..<colon])
        }
        return value.isEmpty ? nil : value
    }

    static func isOwnProcess(_ name: String, pid: Int) -> Bool {
        if pid == Int(ProcessInfo.processInfo.processIdentifier) { return true }
        return name.lowercased() == ownProcessName
    }
}
