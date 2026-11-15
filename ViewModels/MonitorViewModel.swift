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
            trimmed.trim(retention: retention.interval, now: Date())
            snapshot = trimmed
            scheduleSave(immediately: true)
        }
    }

    private static let recordingKey = "LanFi.monitor.recording"
    private static let retentionKey = "LanFi.monitor.retention"
    private let store = MonitorStore()
    private var saveTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let savedRecording = defaults.object(forKey: Self.recordingKey) as? Bool ?? true
        let savedRetention =
            MonitorRetention(rawValue: defaults.string(forKey: Self.retentionKey) ?? "")
            ?? .day
        isRecording = savedRecording
        retention = savedRetention

        var loaded = store.load()
        loaded.trim(retention: savedRetention.interval, now: Date())
        snapshot = loaded
    }

    var samples: [MonitorSample] { snapshot.samples }
    var events: [MonitorEvent] { snapshot.events }
    var lastSample: MonitorSample? { snapshot.samples.last }
    var statistics: HistoryStatistics? { snapshot.statistics }
    var csv: String { MonitorCSV.make(samples: snapshot.samples) }

    func ingest(connected: NetworkModel?) {
        guard isRecording else { return }

        var updated = snapshot
        let changed = updated.ingest(
            connected: connected, now: Date(), sampleInterval: retention.sampleInterval)
        snapshot = updated
        if changed { scheduleSave() }
    }

    func clear() {
        saveTask?.cancel()
        saveTask = nil
        snapshot = .empty
        store.clear()
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
