import LanFiCore
import Foundation
import SwiftUI

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var snapshot: MonitorSnapshot
    @Published var isRecording: Bool = true {
        didSet {
            UserDefaults.standard.set(isRecording, forKey: Self.recordingKey)
            if !isRecording { scheduleSave(immediately: true) }
        }
    }
    @Published var retention: MonitorRetention = .day {
        didSet {
            UserDefaults.standard.set(retention.rawValue, forKey: Self.retentionKey)
            var trimmed = snapshot
            trimmed.trim(retention: retention.interval, now: clock.now)
            snapshot = trimmed
            scheduleSave(immediately: true)
        }
    }
    @Published var alerts: MonitorAlertSettings = .default {
        didSet { saveAlerts() }
    }

    private static let recordingKey = AppSettingsKey.monitorRecording.rawValue
    private static let retentionKey = AppSettingsKey.monitorRetention.rawValue
    private static let alertsKey = AppSettingsKey.monitorAlerts.rawValue
    private let store: MonitorStore
    private let notifier: any MonitorNotifying
    /// Injected so the retention trim and event timestamps are reproducible.
    private let clock: any Clock
    private var saveTask: Task<Void, Never>?

    init(
        clock: any Clock = SystemClock(),
        store: MonitorStore = MonitorStore(),
        notifier: (any MonitorNotifying)? = nil
    ) {
        self.clock = clock
        self.store = store
        self.notifier = notifier ?? MonitorNotifier()
        let defaults = UserDefaults.standard
        let savedRecording = defaults.object(forKey: Self.recordingKey) as? Bool ?? true
        let savedRetention =
            MonitorRetention(rawValue: defaults.string(forKey: Self.retentionKey) ?? "")
            ?? .day
        isRecording = savedRecording
        retention = savedRetention
        if let data = defaults.data(forKey: Self.alertsKey),
            let decoded = try? JSONDecoder().decode(MonitorAlertSettings.self, from: data)
        {
            alerts = decoded
        }

        var loaded = store.load()
        loaded.trim(retention: savedRetention.interval, now: clock.now)
        snapshot = loaded
    }

    var samples: [MonitorSample] { snapshot.samples }
    var events: [MonitorEvent] { snapshot.events }
    var peers: [MonitorPeer] {
        snapshot.peers.values.sorted { $0.averageRSSI > $1.averageRSSI }
    }
    var lastSample: MonitorSample? { snapshot.samples.last }
    var statistics: HistoryStatistics? { snapshot.statistics }
    var csv: String { MonitorCSV.make(samples: snapshot.samples) }
    var peersCSV: String { MonitorCSV.make(peers: peers) }

    func ingest(connected: NetworkModel?, visible: [NetworkModel] = []) {
        guard isRecording else { return }

        let previousEventIDs = Set(snapshot.events.map(\.id))
        var updated = snapshot
        let changed = updated.ingest(
            connected: connected, visible: visible, now: clock.now,
            sampleInterval: retention.sampleInterval)
        snapshot = updated
        for event in updated.events where !previousEventIDs.contains(event.id) {
            notifier.notify(event, settings: alerts)
        }
        if changed { scheduleSave() }
    }

    func ingestCapture(_ report: CaptureSecurityReport) {
        guard isRecording else { return }
        let previousEventIDs = Set(snapshot.events.map(\.id))
        var updated = snapshot
        guard updated.ingestCapture(report) else { return }
        snapshot = updated
        for event in updated.events where !previousEventIDs.contains(event.id) {
            notifier.notify(event, settings: alerts)
        }
        scheduleSave()
    }

    func requestNotificationPermission() async -> Bool {
        await notifier.requestAuthorization()
    }

    func clear() {
        saveTask?.cancel()
        saveTask = nil
        snapshot = .empty
        store.clear()
    }

    private func saveAlerts() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        UserDefaults.standard.set(data, forKey: Self.alertsKey)
    }

    private func scheduleSave(immediately: Bool = false) {
        saveTask?.cancel()
        let snapshot = snapshot
        let retention = retention
        let store = store
        saveTask = Task {
            if !immediately {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            guard !Task.isCancelled else { return }
            store.save(snapshot, retention: retention)
        }
    }
}
