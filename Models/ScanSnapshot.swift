import AppKit
import Foundation

/// One network as it looked in a saved scan. Only fields that make a diff
/// meaningful are kept: identity, placement and security.
struct ScanSnapshotNetwork: Codable, Equatable, Identifiable {
    let bssid: String
    let ssid: String
    let band: String
    let channel: Int
    let widthMHz: Int
    let security: String
    let rssi: Int
    let vendor: String
    let generation: String

    var id: String { bssid.isEmpty ? "\(ssid)|\(band)|\(channel)" : bssid }
}

struct ScanSnapshot: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String
    var note: String
    var createdAt: Date
    var networks: [ScanSnapshotNetwork]

    init(
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
struct ScanSnapshotDiff: Equatable {
    struct FieldChange: Identifiable, Equatable {
        let bssid: String
        let ssid: String
        let field: String
        let from: String
        let to: String

        var id: String { "\(bssid)-\(field)" }
        var summary: String { "\(field): \(from) → \(to)" }
    }

    let before: ScanSnapshot
    let after: ScanSnapshot
    let added: [ScanSnapshotNetwork]
    let removed: [ScanSnapshotNetwork]
    let changed: [FieldChange]
    let rssiThreshold: Int

    var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }
    var changeCount: Int { added.count + removed.count + changed.count }

    /// `before` is the older snapshot, `after` the newer one. A signal shift is
    /// only reported when it crosses `rssiThreshold`, because ±3 dBm is normal
    /// scan noise and would bury the channel/security changes that matter.
    static func compare(
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
            record(String(localized: "SSID"), previous.ssid, network.ssid)
            record(String(localized: "Band"), previous.band, network.band)
            record(String(localized: "Channel"), "\(previous.channel)", "\(network.channel)")
            record(String(localized: "Width"), "\(previous.widthMHz)", "\(network.widthMHz)")
            record(String(localized: "Security"), previous.security, network.security)
            record(String(localized: "Generation"), previous.generation, network.generation)
            if abs(network.rssi - previous.rssi) >= rssiThreshold {
                changed.append(
                    FieldChange(
                        bssid: network.bssid, ssid: network.ssid,
                        field: String(localized: "Signal"),
                        from: "\(previous.rssi) dBm", to: "\(network.rssi) dBm"))
            }
        }

        return ScanSnapshotDiff(
            before: before, after: after,
            added: added.sorted { $0.ssid == $1.ssid ? $0.id < $1.id : $0.ssid < $1.ssid },
            removed: removed.sorted { $0.ssid == $1.ssid ? $0.id < $1.id : $0.ssid < $1.ssid },
            changed: changed.sorted {
                $0.ssid == $1.ssid ? ($0.bssid, $0.field) < ($1.bssid, $1.field) : $0.ssid < $1.ssid
            },
            rssiThreshold: rssiThreshold)
    }

    var csv: String {
        var rows = [
            "change,bssid,ssid,band,channel,width_mhz,security,rssi,field,from,to"
        ]
        for network in added {
            rows.append(
                [
                    "added", network.bssid, network.ssid, network.band, "\(network.channel)",
                    "\(network.widthMHz)", network.security, "\(network.rssi)", "", "", "",
                ].map(Self.csvField).joined(separator: ","))
        }
        for network in removed {
            rows.append(
                [
                    "removed", network.bssid, network.ssid, network.band, "\(network.channel)",
                    "\(network.widthMHz)", network.security, "\(network.rssi)", "", "", "",
                ].map(Self.csvField).joined(separator: ","))
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

    static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Snapshots persist as one JSON file in Application Support, like GPS trips.
struct ScanSnapshotStore {
    let url: URL

    init(url: URL = ScanSnapshotStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("scan-snapshots.json")
    }

    func load() -> [ScanSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ScanSnapshot].self, from: data)) ?? []
    }

    func save(_ snapshots: [ScanSnapshot]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshots).write(to: url, options: .atomic)
    }

    @discardableResult
    func add(_ snapshot: ScanSnapshot) throws -> [ScanSnapshot] {
        var snapshots = load()
        snapshots.append(snapshot)
        try save(snapshots)
        return snapshots
    }

    @discardableResult
    func delete(id: UUID) throws -> [ScanSnapshot] {
        var snapshots = load()
        snapshots.removeAll { $0.id == id }
        try save(snapshots)
        return snapshots
    }
}

// MARK: - Building a snapshot from a live scan

enum ScanSnapshotBuilder {
    static func network(from model: NetworkModel) -> ScanSnapshotNetwork {
        ScanSnapshotNetwork(
            bssid: model.bssid.uppercased(),
            ssid: model.ssid,
            band: model.band.label,
            channel: model.channel,
            widthMHz: model.channelWidthMHz,
            security: model.security,
            rssi: model.signal,
            vendor: model.vendor,
            generation: model.generation.label)
    }

    static func snapshot(
        label: String, note: String = "", networks: [NetworkModel], now: Date = Date()
    ) -> ScanSnapshot {
        ScanSnapshot(
            label: label, note: note, createdAt: now,
            networks: networks.map(network(from:)).sorted { $0.id < $1.id })
    }
}

extension Notification.Name {
    /// Posted after a snapshot is saved or deleted so an open comparison window
    /// reloads instead of showing a stale list.
    static let lanFiSnapshotsChanged = Notification.Name("LanFi.snapshotsChanged")
}

@MainActor
enum ScanSnapshotActions {
    static func promptSave(networks: [NetworkModel], store: ScanSnapshotStore = .init()) {
        guard !networks.isEmpty else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        field.stringValue = defaultLabel()
        let alert = NSAlert()
        alert.messageText = "Save scan snapshot"
        alert.informativeText =
            "Snapshots are local; compare two of them later to see what changed."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = ScanSnapshotBuilder.snapshot(
            label: name.isEmpty ? defaultLabel() : name, networks: networks)
        do {
            try store.add(snapshot)
            NotificationCenter.default.post(name: .lanFiSnapshotsChanged, object: nil)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Could not save the snapshot"
            failure.informativeText = error.localizedDescription
            failure.runModal()
        }
    }

    static func defaultLabel(now: Date = Date()) -> String {
        "Scan " + now.formatted(date: .abbreviated, time: .shortened)
    }
}
