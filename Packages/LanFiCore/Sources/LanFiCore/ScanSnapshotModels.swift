import Foundation

/// One network as it looked in a saved scan. Only fields that make a diff
/// meaningful are kept: identity, placement and security.
public struct ScanSnapshotNetwork: Codable, Equatable, Identifiable, Sendable {
    public let bssid: String
    public let ssid: String
    public let band: String
    public let channel: Int
    public let widthMHz: Int
    public let security: String
    public let rssi: Int
    public let vendor: String
    public let generation: String

    public init(
        bssid: String, ssid: String, band: String, channel: Int, widthMHz: Int,
        security: String, rssi: Int, vendor: String, generation: String
    ) {
        self.bssid = bssid
        self.ssid = ssid
        self.band = band
        self.channel = channel
        self.widthMHz = widthMHz
        self.security = security
        self.rssi = rssi
        self.vendor = vendor
        self.generation = generation
    }

    public var id: String { bssid.isEmpty ? "\(ssid)|\(band)|\(channel)" : bssid }
}

public struct ScanSnapshot: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var label: String
    public var note: String
    public var createdAt: Date
    public var networks: [ScanSnapshotNetwork]

    public init(
        id: UUID = UUID(), label: String, note: String = "", createdAt: Date = Date(),
        networks: [ScanSnapshotNetwork]
    ) {
        self.id = id
        self.label = label
        self.note = note
        self.createdAt = createdAt
        self.networks = networks
    }
}

/// What changed between two scans of the same place.
public struct ScanSnapshotDiff: Equatable, Sendable {
    public struct FieldChange: Identifiable, Equatable, Sendable {
        public let bssid: String
        public let ssid: String
        public let field: String
        public let from: String
        public let to: String

        public init(bssid: String, ssid: String, field: String, from: String, to: String) {
            self.bssid = bssid
            self.ssid = ssid
            self.field = field
            self.from = from
            self.to = to
        }

        public var id: String { "\(bssid)-\(field)" }
        public var summary: String { "\(field): \(from) → \(to)" }
    }

    public let before: ScanSnapshot
    public let after: ScanSnapshot
    public let added: [ScanSnapshotNetwork]
    public let removed: [ScanSnapshotNetwork]
    public let changed: [FieldChange]
    public let rssiThreshold: Int

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
    public var changeCount: Int { added.count + removed.count + changed.count }

    /// `before` is the older snapshot, `after` the newer one. A signal shift is
    /// only reported when it crosses `rssiThreshold`, because ±3 dBm is normal
    /// scan noise and would bury the channel/security changes that matter.
    public static func compare(
        before: ScanSnapshot, after: ScanSnapshot, rssiThreshold: Int = 10
    ) -> ScanSnapshotDiff {
        let old = Dictionary(uniqueKeysWithValues: before.networks.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: after.networks.map { ($0.id, $0) })

        let added = after.networks.filter { old[$0.id] == nil }
        let removed = before.networks.filter { new[$0.id] == nil }

        var changed: [FieldChange] = []
        for network in after.networks {
            guard let previous = old[network.id] else { continue }
            func record(_ field: String, _ from: String, _ to: String) {
                guard from != to else { return }
                changed.append(
                    FieldChange(
                        bssid: network.bssid, ssid: network.ssid, field: field, from: from,
                        to: to))
            }
            record("SSID", previous.ssid, network.ssid)
            record("Band", previous.band, network.band)
            record("Channel", "\(previous.channel)", "\(network.channel)")
            record("Width", "\(previous.widthMHz)", "\(network.widthMHz)")
            record("Security", previous.security, network.security)
            record("Generation", previous.generation, network.generation)
            if abs(network.rssi - previous.rssi) >= rssiThreshold {
                changed.append(
                    FieldChange(
                        bssid: network.bssid, ssid: network.ssid, field: "Signal",
                        from: "\(previous.rssi) dBm", to: "\(network.rssi) dBm"))
            }
        }

        return ScanSnapshotDiff(
            before: before, after: after,
            added: added.sorted { $0.ssid == $1.ssid ? $0.id < $1.id : $0.ssid < $1.ssid },
            removed: removed.sorted { $0.ssid == $1.ssid ? $0.id < $1.id : $0.ssid < $1.ssid },
            changed: changed.sorted {
                $0.ssid == $1.ssid
                    ? ($0.bssid, $0.field) < ($1.bssid, $1.field) : $0.ssid < $1.ssid
            },
            rssiThreshold: rssiThreshold)
    }

    public init(
        before: ScanSnapshot, after: ScanSnapshot, added: [ScanSnapshotNetwork],
        removed: [ScanSnapshotNetwork], changed: [FieldChange], rssiThreshold: Int
    ) {
        self.before = before
        self.after = after
        self.added = added
        self.removed = removed
        self.changed = changed
        self.rssiThreshold = rssiThreshold
    }

    public var csv: String {
        var rows = ["change,bssid,ssid,band,channel,width_mhz,security,rssi,field,from,to"]
        for network in added {
            rows.append(
                csvRow("added", network: network)
            )
        }
        for network in removed {
            rows.append(
                csvRow("removed", network: network)
            )
        }
        for change in changed {
            rows.append(
                [
                    "changed", change.bssid, change.ssid, "", "", "", "", "", change.field,
                    change.from, change.to,
                ].map(Self.csvField).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private func csvRow(_ kind: String, network: ScanSnapshotNetwork) -> String {
        [
            kind, network.bssid, network.ssid, network.band, "\(network.channel)",
            "\(network.widthMHz)", network.security, "\(network.rssi)", "", "", "",
        ].map(Self.csvField).joined(separator: ",")
    }

    public static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Snapshots persist as one JSON file in Application Support, like GPS trips.
public struct ScanSnapshotStore: Sendable {
    public let url: URL

    public init(url: URL = ScanSnapshotStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("scan-snapshots.json")
    }

    public func load() -> [ScanSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScanSnapshot].self, from: data)) ?? []
    }

    public func save(_ snapshots: [ScanSnapshot]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshots).write(to: url, options: .atomic)
    }

    @discardableResult
    public func add(_ snapshot: ScanSnapshot) throws -> [ScanSnapshot] {
        var snapshots = load()
        snapshots.append(snapshot)
        try save(snapshots)
        return snapshots
    }

    @discardableResult
    public func delete(id: UUID) throws -> [ScanSnapshot] {
        var snapshots = load()
        snapshots.removeAll { $0.id == id }
        try save(snapshots)
        return snapshots
    }
}
