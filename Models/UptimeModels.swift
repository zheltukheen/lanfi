import Foundation

enum UptimeTargetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case tcp
    case tls
    case dns
    case mail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: return String(localized: "HTTP / HTTPS")
        case .tcp: return String(localized: "TCP port")
        case .tls: return String(localized: "TLS certificate")
        case .dns: return String(localized: "DNS record")
        case .mail: return String(localized: "Mail records")
        }
    }
}

struct UptimeTarget: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var address: String
    var kind: UptimeTargetKind
    var intervalMinutes: Int
    var enabled: Bool
    var createdAt: Date

    /// Three public services that answer quickly from almost anywhere. They
    /// are seeded on first launch so the monitor shows live data immediately
    /// instead of an empty list.
    static var starterTargets: [UptimeTarget] {
        [
            UptimeTarget(
                name: "Cloudflare DNS", address: "https://1.1.1.1", kind: .http,
                intervalMinutes: 5),
            UptimeTarget(
                name: "Google", address: "https://www.google.com", kind: .http,
                intervalMinutes: 5),
            UptimeTarget(
                name: "GitHub", address: "https://github.com", kind: .http,
                intervalMinutes: 5),
        ]
    }

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        kind: UptimeTargetKind,
        intervalMinutes: Int,
        enabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.kind = kind
        self.intervalMinutes = max(1, min(intervalMinutes, 24 * 60))
        self.enabled = enabled
        self.createdAt = createdAt
    }

    /// Builds a target from a user-entered name and address, normalising the
    /// address for the chosen kind. Returns nil when the address is invalid.
    static func make(
        name: String,
        address: String,
        kind: UptimeTargetKind,
        intervalMinutes: Int
    ) -> UptimeTarget? {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return nil }

        let normalized: String
        switch kind {
        case .http:
            let withScheme =
                trimmedAddress.contains("://") ? trimmedAddress : "https://\(trimmedAddress)"
            guard let components = URLComponents(string: withScheme),
                let scheme = components.scheme?.lowercased(),
                scheme == "http" || scheme == "https",
                let host = components.host, !host.isEmpty
            else { return nil }
            normalized = components.url?.absoluteString ?? withScheme
        case .tcp:
            guard let target = ToolTarget.parse(trimmedAddress), let port = target.port, port > 0
            else { return nil }
            normalized = "\(target.host):\(port)"
        case .tls:
            guard let target = ToolTarget.parse(trimmedAddress, defaultPort: 443),
                let port = target.port, port > 0
            else { return nil }
            normalized = "\(target.host):\(port)"
        case .dns, .mail:
            guard let target = ToolTarget.parse(trimmedAddress) else { return nil }
            normalized = target.host
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return UptimeTarget(
            name: trimmedName.isEmpty ? trimmedAddress : trimmedName,
            address: normalized,
            kind: kind,
            intervalMinutes: intervalMinutes
        )
    }

    var httpURL: URL? {
        guard kind == .http else { return nil }
        return URL(string: address)
    }

    var tcpTarget: ToolTarget? {
        guard kind == .tcp else { return nil }
        return ToolTarget.parse(address)
    }

    var tlsTarget: ToolTarget? {
        guard kind == .tls else { return nil }
        return ToolTarget.parse(address)
    }

    var dnsHost: String? {
        guard kind == .dns else { return nil }
        return ToolTarget.parse(address)?.host
    }

    var mailDomain: String? {
        guard kind == .mail else { return nil }
        return ToolTarget.parse(address)?.host
    }

    var kindIcon: String {
        switch kind {
        case .http: return "globe"
        case .tcp: return "network"
        case .tls: return "lock.shield"
        case .dns: return "magnifyingglass"
        case .mail: return "envelope.badge.shield.half.filled"
        }
    }
}

struct UptimeCheck: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let targetID: UUID
    let at: Date
    let isUp: Bool
    let latencyMilliseconds: Double?
    let detail: String?

    init(
        id: UUID = UUID(),
        targetID: UUID,
        at: Date = Date(),
        isUp: Bool,
        latencyMilliseconds: Double? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.targetID = targetID
        self.at = at
        self.isUp = isUp
        self.latencyMilliseconds = latencyMilliseconds
        self.detail = detail
    }
}

enum UptimeEvent: Equatable, Sendable {
    case down
    case recovered
}

enum UptimeTransition {
    static func event(previousUp: Bool?, currentUp: Bool) -> UptimeEvent? {
        guard let previousUp else { return currentUp ? nil : .down }
        if previousUp, !currentUp { return .down }
        if !previousUp, currentUp { return .recovered }
        return nil
    }
}

struct UptimeTargetState: Identifiable, Equatable, Sendable {
    let target: UptimeTarget
    let lastCheck: UptimeCheck?
    let uptimePercent: Double?
    let averageLatencyMilliseconds: Double?
    let outageCount: Int
    let checks: [UptimeCheck]

    var id: UUID { target.id }
    var isUp: Bool? { lastCheck?.isUp }
}

struct UptimeStoreSnapshot: Codable, Equatable, Sendable {
    var targets: [UptimeTarget]
    var checks: [UptimeCheck]

    static let empty = UptimeStoreSnapshot(targets: [], checks: [])
}
