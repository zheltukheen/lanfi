import Foundation

final class UptimeStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let retention: TimeInterval
    private let maximumChecks: Int

    init(
        directory: URL? = nil,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        maximumChecks: Int = 5_000
    ) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("uptime.json")
        self.retention = retention
        self.maximumChecks = max(100, maximumChecks)
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load(now: Date = Date()) -> UptimeStoreSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
            let snapshot = try? decoder.decode(UptimeStoreSnapshot.self, from: data)
        else { return .empty }
        return trim(snapshot, now: now)
    }

    func save(_ snapshot: UptimeStoreSnapshot, now: Date = Date()) {
        let trimmed = trim(snapshot, now: now)
        guard let data = try? encoder.encode(trimmed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func trim(_ snapshot: UptimeStoreSnapshot, now: Date) -> UptimeStoreSnapshot {
        let cutoff = now.addingTimeInterval(-retention)
        var checks = snapshot.checks.filter { $0.at >= cutoff }
        if checks.count > maximumChecks {
            checks = Array(checks.suffix(maximumChecks))
        }
        return UptimeStoreSnapshot(targets: snapshot.targets, checks: checks)
    }
}
