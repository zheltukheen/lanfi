import AppKit
import Foundation
import LanFiCore

// The snapshot value, diff and JSON store live in LanFiCore so the CLI, tests
// and any future app target share one implementation. These aliases keep the
// app-side spelling unchanged.
typealias ScanSnapshotNetwork = LanFiCore.ScanSnapshotNetwork
typealias ScanSnapshot = LanFiCore.ScanSnapshot
typealias ScanSnapshotDiff = LanFiCore.ScanSnapshotDiff
typealias ScanSnapshotStore = LanFiCore.ScanSnapshotStore

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
