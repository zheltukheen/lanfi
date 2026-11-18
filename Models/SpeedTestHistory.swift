import Foundation

/// The Wi-Fi network a speed test ran on. Optional so old history files keep
/// decoding: measurements written before per-network grouping have no owner.
struct SpeedTestNetwork: Codable, Equatable, Sendable {
    let ssid: String
    let bssid: String?

    /// Groups all radios of one SSID together; hidden networks fall back to the
    /// BSSID, and a fully unknown test gets its own bucket.
    var key: String {
        ssid.isEmpty ? (bssid?.uppercased() ?? "unknown") : ssid.lowercased()
    }

    var displayName: String {
        if !ssid.isEmpty { return ssid }
        if let bssid { return bssid }
        return String(localized: "Unknown network")
    }
}

struct ThroughputMeasurement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let report: ThroughputReport
    let network: SpeedTestNetwork?

    init(id: UUID = UUID(), report: ThroughputReport, network: SpeedTestNetwork? = nil) {
        self.id = id
        self.report = report
        self.network = network
    }

    var testedAt: Date { report.testedAt }
    var bufferbloatGrade: String? { report.bufferbloatGrade }
}

/// One network's tests, newest first, with the deltas the history screen shows.
struct SpeedTestNetworkHistory: Identifiable, Equatable {
    let network: SpeedTestNetwork
    let measurements: [ThroughputMeasurement]

    var id: String { network.key }
    var latest: ThroughputMeasurement? { measurements.first }
    var previous: ThroughputMeasurement? { measurements.dropFirst().first }
    var testCount: Int { measurements.count }

    var averageDownloadMbps: Double? { average(measurements.map { $0.report.downloadMbps }) }
    var averageUploadMbps: Double? { average(measurements.map { $0.report.uploadMbps }) }

    var downloadDeltaMbps: Double? {
        delta(latest?.report.downloadMbps, previous?.report.downloadMbps)
    }

    var uploadDeltaMbps: Double? {
        delta(latest?.report.uploadMbps, previous?.report.uploadMbps)
    }

    var latencyDeltaMilliseconds: Double? {
        delta(latest?.report.latencyMilliseconds, previous?.report.latencyMilliseconds)
    }

    private func average(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +) / Double(present.count)
    }

    private func delta(_ latest: Double?, _ previous: Double?) -> Double? {
        guard let latest, let previous else { return nil }
        return latest - previous
    }
}

enum SpeedTestHistoryIndex {
    /// Tests grouped by network, most recently tested first. Tests without a
    /// recorded network stay out of the per-network list; the All view still
    /// shows them.
    static func groups(_ measurements: [ThroughputMeasurement]) -> [SpeedTestNetworkHistory] {
        let attributed = measurements.filter { $0.network != nil }
        let grouped = Dictionary(grouping: attributed) { $0.network!.key }
        return
            grouped
            .compactMap { _, items -> SpeedTestNetworkHistory? in
                guard let network = items.first?.network else { return nil }
                return SpeedTestNetworkHistory(
                    network: network,
                    measurements: items.sorted { $0.testedAt > $1.testedAt })
            }
            .sorted {
                ($0.latest?.testedAt ?? .distantPast) > ($1.latest?.testedAt ?? .distantPast)
            }
    }

    static func measurements(
        _ measurements: [ThroughputMeasurement], for key: String?
    ) -> [ThroughputMeasurement] {
        let filtered =
            key == nil
            ? measurements
            : measurements.filter { $0.network?.key == key }
        return filtered.sorted { $0.testedAt > $1.testedAt }
    }
}

enum SpeedTestSchedule: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case hourly
    case everySixHours
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .hourly: return String(localized: "Every hour")
        case .everySixHours: return String(localized: "Every 6 hours")
        case .daily: return String(localized: "Once a day")
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
