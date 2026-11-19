import Foundation

/// P3.6 — per-app traffic history, folded from the same `nettop` deltas the
/// Process Traffic screen shows.
///
/// Only byte counts are stored: no domain, URL, payload or cookie ever reaches
/// the ledger. Buckets are hourly so a day can be aggregated exactly, and LanFi's
/// own process is excluded because its own scans are not the user's traffic.
struct AppTrafficHistory: Codable, Equatable, Sendable {
    /// app name -> hour key ("yyyy-MM-dd'T'HH") -> volume.
    var apps: [String: [String: TrafficVolume]] = [:]
    var updatedAt: Date?

    static let empty = AppTrafficHistory()
    static let retentionDays = 7

    static func hourKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d", components.year ?? 0, components.month ?? 0,
            components.day ?? 0, components.hour ?? 0)
    }

    static func dayPrefix(_ date: Date, calendar: Calendar = .current) -> String {
        TrafficLedger.dayKey(date, calendar: calendar)
    }

    mutating func record(
        _ deltas: [ProcessTrafficDelta],
        at date: Date,
        excludingPIDs: Set<Int> = [],
        calendar: Calendar = .current
    ) {
        let key = Self.hourKey(date, calendar: calendar)
        var recorded = false
        for delta in deltas {
            guard !excludingPIDs.contains(delta.pid) else { continue }
            guard delta.receivedBytes > 0 || delta.sentBytes > 0 else { continue }
            apps[delta.process, default: [:]][key, default: TrafficVolume()] += TrafficVolume(
                received: delta.receivedBytes, sent: delta.sentBytes)
            recorded = true
        }
        if recorded { updatedAt = date }
    }

    func volume(forApp app: String, on day: Date = Date(), calendar: Calendar = .current)
        -> TrafficVolume
    {
        let prefix = Self.dayPrefix(day, calendar: calendar)
        return (apps[app] ?? [:]).reduce(TrafficVolume()) { partial, entry in
            guard entry.key.hasPrefix(prefix) else { return partial }
            return partial + entry.value
        }
    }

    func dayTotal(on day: Date = Date(), calendar: Calendar = .current) -> TrafficVolume {
        apps.keys.reduce(TrafficVolume()) { $0 + volume(forApp: $1, on: day, calendar: calendar) }
    }

    func topApps(on day: Date = Date(), limit: Int = 6, calendar: Calendar = .current)
        -> [(app: String, volume: TrafficVolume)]
    {
        apps.map { (app: $0.key, volume: volume(forApp: $0.key, on: day, calendar: calendar)) }
            .filter { !$0.volume.isEmpty }
            .sorted { lhs, rhs in
                if lhs.volume.total != rhs.volume.total { return lhs.volume.total > rhs.volume.total }
                return lhs.app.localizedStandardCompare(rhs.app) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    mutating func prune(
        now: Date = Date(), keepDays: Int = retentionDays, calendar: Calendar = .current
    ) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) else { return }
        let cutoffPrefix = Self.dayPrefix(cutoff, calendar: calendar)
        for app in apps.keys {
            apps[app] = (apps[app] ?? [:]).filter {
                String($0.key.prefix(10)) >= cutoffPrefix
            }
        }
        apps = apps.filter { !$0.value.isEmpty }
    }

    /// CSV of the aggregated per-app totals for one day.
    func csv(on day: Date = Date(), calendar: Calendar = .current) -> String {
        var lines = ["date,app,received_bytes,sent_bytes"]
        for (app, volume) in topApps(on: day, limit: Int.max, calendar: calendar) {
            lines.append(
                "\(Self.dayPrefix(day, calendar: calendar)),\"\(app)\",\(volume.received),\(volume.sent)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
