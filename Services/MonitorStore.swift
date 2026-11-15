import Foundation

/// Persists the rolling Wi-Fi monitor snapshot next to the other LanFi stores.
final class MonitorStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("monitor.json")
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() -> MonitorSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
            let snapshot = try? decoder.decode(MonitorSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    func save(_ snapshot: MonitorSnapshot, retention: MonitorRetention, now: Date = Date()) {
        var trimmed = snapshot
        trimmed.trim(retention: retention.interval, now: now)
        guard let data = try? encoder.encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
