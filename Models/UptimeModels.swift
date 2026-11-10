import Foundation

enum UptimeTargetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case http
    case tcp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http: return "HTTP / HTTPS"
        case .tcp: return "TCP port"
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

    var kindIcon: String {
        kind == .http ? "globe" : "network"
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
