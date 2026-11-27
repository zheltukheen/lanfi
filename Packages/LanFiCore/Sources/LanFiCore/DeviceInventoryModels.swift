import Foundation

/// What a discovered LAN device most likely is, inferred from what it
/// advertises rather than from an authenticated inventory.
public enum DeviceRole: String, Codable, CaseIterable, Sendable {
    case router
    case accessPoint
    case printer
    case mediaDevice
    case smartHome
    case storage
    case computer
    case camera
    case phone
    case networkDevice
}

/// Why a role was chosen. Only an advertised role is the device's own claim;
/// everything else is this app's inference and is labelled as such in the UI.
public enum DeviceRoleBasis: String, Codable, Sendable {
    case advertised
    case services
    case openPorts
    case vendor
}

public struct DeviceRoleGuess: Equatable, Sendable {
    public let role: DeviceRole
    public let basis: DeviceRoleBasis

    public init(role: DeviceRole, basis: DeviceRoleBasis) {
        self.role = role
        self.basis = basis
    }

    public var isInferred: Bool { basis != .advertised }
}

/// Labels a device from the evidence LanFi already collects: a role the device
/// published (UPnP/Bonjour), the services it advertises, its open ports and the
/// MAC vendor. The first tiers are ordered strongest to weakest, and the
/// returned basis records which tier answered.
public enum DeviceRoleClassifier {
    public static func guess(
        advertisedRole: String?, services: [String], openPorts: [UInt16], vendor: String?,
        hostname: String?
    ) -> DeviceRoleGuess? {
        if let advertisedRole, let role = role(fromText: advertisedRole) {
            return DeviceRoleGuess(role: role, basis: .advertised)
        }
        let labels = services.joined(separator: " ").lowercased()
        if !labels.isEmpty, let role = role(fromText: labels) {
            return DeviceRoleGuess(role: role, basis: .services)
        }
        if let role = role(fromPorts: openPorts) {
            return DeviceRoleGuess(role: role, basis: .openPorts)
        }
        let vendorText = [vendor, hostname].compactMap { $0 }.joined(separator: " ").lowercased()
        if !vendorText.isEmpty, let role = role(fromText: vendorText) ?? role(fromVendor: vendorText) {
            return DeviceRoleGuess(role: role, basis: .vendor)
        }
        return nil
    }

    private static func role(fromText text: String) -> DeviceRole? {
        let value = text.lowercased()
        let rules: [(DeviceRole, [String])] = [
            (.printer, ["printer", "printing", "airprint", "ipp"]),
            (.mediaDevice, ["airplay", "googlecast", "cast", "plex", "media", "spotify", "sonos"]),
            (.smartHome, ["homekit", "matter", "smart home", "home assistant"]),
            (.storage, ["nas", "file sharing", "smb", "afp", "time capsule", "file server"]),
            (.camera, ["camera", "ipcam", "onvif", "nvr"]),
            (.accessPoint, ["access point", "wireless ap", "wi-fi ap", "mesh node"]),
            (.router, ["internet gateway", "router", "gateway", "firewall"]),
            (.computer, ["workstation", "computer", "laptop", "desktop", "server"]),
            (.phone, ["phone", "iphone", "ipad", "tablet"]),
        ]
        return rules.first { _, keywords in keywords.contains(where: value.contains) }?.0
    }

    private static func role(fromPorts ports: [UInt16]) -> DeviceRole? {
        let open = Set(ports)
        if open.contains(9100) || open.contains(515) || open.contains(631) { return .printer }
        if open.contains(32400) || open.contains(7000) { return .mediaDevice }
        if open.contains(554) || open.contains(8554) { return .camera }
        if open.contains(445) || open.contains(548) || open.contains(139) { return .storage }
        if open.contains(62078) { return .phone }
        if open.contains(22) || open.contains(3389) { return .computer }
        // A web UI alone says nothing: almost every device has one, and letting
        // it answer here would stop the vendor tier from ever running.
        return nil
    }

    private static func role(fromVendor text: String) -> DeviceRole? {
        let rules: [(DeviceRole, [String])] = [
            (.storage, ["synology", "qnap", "drobo", "western digital", "netgear readynas"]),
            (
                .printer,
                [
                    "hewlett", "brother", "epson", "canon", "xerox", "lexmark", "ricoh", "kyocera",
                ]
            ),
            (.camera, ["hikvision", "dahua", "axis communications", "reolink", "hanwha"]),
            (
                .accessPoint,
                [
                    "ubiquiti", "aruba", "ruckus", "cisco", "meraki", "tp-link", "netgear",
                    "zyxel", "extreme networks",
                ]
            ),
            (.mediaDevice, ["sonos", "roku", "google", "amazon", "sony", "lg electronics", "vizio"]),
            (.phone, ["samsung electronics", "xiaomi", "oneplus", "huawei"]),
            (.computer, ["apple", "intel", "dell", "lenovo", "asus", "micro-star", "gigabyte"]),
        ]
        return rules.first { _, keywords in keywords.contains(where: text.contains) }?.0
    }
}

/// One device as a scan saw it, in the smallest shape a baseline needs.
public struct LANDeviceRecord: Equatable, Sendable {
    /// MAC when the ARP table had one, the IP otherwise.
    public let key: String
    public let name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

public struct DeviceInventoryEntry: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var firstSeen: Date
    public var lastSeen: Date
    /// False until the user says the device belongs on this network.
    public var authorized: Bool

    public init(
        key: String, name: String, firstSeen: Date, lastSeen: Date, authorized: Bool = false
    ) {
        self.key = key
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.authorized = authorized
    }
}

public struct DeviceInventoryState: Codable, Equatable, Sendable {
    /// Nil until the first scan seeded the inventory; that scan adopts every
    /// device it sees instead of reporting the whole network as new.
    public var seededAt: Date?
    public var entries: [String: DeviceInventoryEntry]

    public init(seededAt: Date? = nil, entries: [String: DeviceInventoryEntry] = [:]) {
        self.seededAt = seededAt
        self.entries = entries
    }

    public static let empty = DeviceInventoryState()

    public var authorizedKeys: Set<String> {
        Set(entries.values.filter(\.authorized).map(\.key))
    }

    /// Marks the given devices as belonging to this network. Unknown keys are
    /// ignored instead of being invented.
    public mutating func authorize(_ keys: Set<String>, now: Date = Date()) {
        for key in keys {
            guard var entry = entries[key] else { continue }
            entry.authorized = true
            entry.lastSeen = max(entry.lastSeen, now)
            entries[key] = entry
        }
    }

    public mutating func authorizeAll(now: Date = Date()) {
        authorize(Set(entries.keys), now: now)
    }
}

public enum DeviceInventoryEvaluator {
    public struct Change: Equatable, Sendable {
        public let state: DeviceInventoryState
        public let added: [LANDeviceRecord]
        /// Known devices that this scan did not see. Shown as a count because a
        /// laptop that changes networks would otherwise report a wall of them.
        public let missing: [DeviceInventoryEntry]
        public let unauthorized: [LANDeviceRecord]
        public let didSeed: Bool

        public init(
            state: DeviceInventoryState, added: [LANDeviceRecord], missing: [DeviceInventoryEntry],
            unauthorized: [LANDeviceRecord], didSeed: Bool
        ) {
            self.state = state
            self.added = added
            self.missing = missing
            self.unauthorized = unauthorized
            self.didSeed = didSeed
        }
    }

    /// Folds one scan into the baseline.
    ///
    /// The first scan seeds silently: a fresh install should not announce that
    /// every device on the network is new. Later scans add unseen keys, refresh
    /// names and last-seen times, and leave authorization exactly as the user
    /// set it.
    public static func evaluate(
        state: DeviceInventoryState, observed: [LANDeviceRecord], now: Date = Date()
    ) -> Change {
        var updated = state
        var added: [LANDeviceRecord] = []
        let seen = Set(observed.map(\.key))
        let didSeed = updated.seededAt == nil

        for record in observed {
            if var entry = updated.entries[record.key] {
                entry.name = record.name
                entry.lastSeen = max(entry.lastSeen, now)
                updated.entries[record.key] = entry
            } else {
                updated.entries[record.key] = DeviceInventoryEntry(
                    key: record.key, name: record.name, firstSeen: now, lastSeen: now)
                if !didSeed { added.append(record) }
            }
        }

        if didSeed { updated.seededAt = now }
        let missing = updated.entries.values
            .filter { !seen.contains($0.key) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let unauthorized = observed.filter { record in
            updated.entries[record.key]?.authorized == false
        }
        return Change(
            state: updated, added: added, missing: missing,
            unauthorized: didSeed ? [] : unauthorized, didSeed: didSeed)
    }
}
