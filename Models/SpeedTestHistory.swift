import Foundation

struct ThroughputMeasurement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let report: ThroughputReport

    init(id: UUID = UUID(), report: ThroughputReport) {
        self.id = id
        self.report = report
    }

    var testedAt: Date { report.testedAt }
    var bufferbloatGrade: String? { report.bufferbloatGrade }
}

enum SpeedTestSchedule: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case hourly
    case everySixHours
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .hourly: return "Every hour"
        case .everySixHours: return "Every 6 hours"
        case .daily: return "Once a day"
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .hourly: return 60 * 60
        case .everySixHours: return 6 * 60 * 60
        case .daily: return 24 * 60 * 60
        }
    }

    func isDue(lastRun: Date?, now: Date = Date()) -> Bool {
        guard let interval else { return false }
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= interval
    }

    func nextRun(after lastRun: Date?) -> Date? {
        guard let interval else { return nil }
        guard let lastRun else { return Date() }
        return lastRun.addingTimeInterval(interval)
    }
}

final class ThroughputHistoryStore {
    private let fileURL: URL
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, limit: Int = 50) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("speed-tests.json")
        self.limit = max(1, limit)
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() -> [ThroughputMeasurement] {
        guard let data = try? Data(contentsOf: fileURL),
            let records = try? decoder.decode([ThroughputMeasurement].self, from: data)
        else { return [] }
        return records.sorted { $0.testedAt < $1.testedAt }.suffix(limit).map { $0 }
    }

    func save(_ records: [ThroughputMeasurement]) {
        let trimmed = records.sorted { $0.testedAt < $1.testedAt }.suffix(limit)
        guard let data = try? encoder.encode(Array(trimmed)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
