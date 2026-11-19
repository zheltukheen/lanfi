import Foundation

/// P2 — traffic accounting. One volume per direction, addable, with the totals
/// the Data usage card shows.
struct TrafficVolume: Codable, Equatable, Sendable {
    var received: UInt64 = 0
    var sent: UInt64 = 0

    var total: UInt64 { received + sent }
    var isEmpty: Bool { received == 0 && sent == 0 }

    static func + (lhs: TrafficVolume, rhs: TrafficVolume) -> TrafficVolume {
        TrafficVolume(received: lhs.received + rhs.received, sent: lhs.sent + rhs.sent)
    }

    static func += (lhs: inout TrafficVolume, rhs: TrafficVolume) {
        lhs = lhs + rhs
    }
}

enum TrafficRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .week: return String(localized: "Last 7 days")
        case .month: return String(localized: "This month")
        case .all: return String(localized: "Total")
        }
    }
}

/// Persisted per-day, per-interface byte counters.
///
/// Days are keyed in the user's calendar, so "today" and "this month" mean what
/// the user sees in Clock and Calendar, and a daylight-saving change cannot
/// shift a day boundary by an hour.
struct TrafficLedger: Codable, Equatable, Sendable {
    var total = TrafficVolume()
    var perDay: [String: TrafficVolume] = [:]
    var perInterface: [String: TrafficVolume] = [:]
    var updatedAt: Date?

    static let empty = TrafficLedger()

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0,
            components.day ?? 0)
    }

    mutating func record(
        received: UInt64, sent: UInt64, interface: String, at date: Date,
        calendar: Calendar = .current
    ) {
        guard received > 0 || sent > 0 else { return }
        let delta = TrafficVolume(received: received, sent: sent)
        total += delta
        perDay[Self.dayKey(date, calendar: calendar), default: TrafficVolume()] += delta
        perInterface[interface, default: TrafficVolume()] += delta
        updatedAt = date
    }

    func volume(for range: TrafficRange, now: Date = Date(), calendar: Calendar = .current)
        -> TrafficVolume
    {
        switch range {
        case .all:
            return total
        case .today:
            return perDay[Self.dayKey(now, calendar: calendar)] ?? TrafficVolume()
        case .week:
            return sum(daysBack: 6, now: now, calendar: calendar)
        case .month:
            guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else {
                return TrafficVolume()
            }
            return perDay.reduce(TrafficVolume()) { partial, entry in
                guard let date = Self.date(from: entry.key, calendar: calendar),
                    date >= monthStart
                else { return partial }
                return partial + entry.value
            }
        }
    }

    private func sum(daysBack: Int, now: Date, calendar: Calendar) -> TrafficVolume {
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else {
            return TrafficVolume()
        }
        let startKey = Self.dayKey(start, calendar: calendar)
        let todayKey = Self.dayKey(now, calendar: calendar)
        return perDay.reduce(TrafficVolume()) { partial, entry in
            guard entry.key >= startKey, entry.key <= todayKey else { return partial }
            return partial + entry.value
        }
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Old days are kept for a year, which is enough for the month and total
    /// views and keeps the file small.
    mutating func prune(now: Date = Date(), keepDays: Int = 400, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) else { return }
        let cutoffKey = Self.dayKey(cutoff, calendar: calendar)
        perDay = perDay.filter { $0.key >= cutoffKey }
    }

    func csv(now: Date = Date(), calendar: Calendar = .current) -> String {
        var lines = ["date,received_bytes,sent_bytes"]
        for key in perDay.keys.sorted() {
            let volume = perDay[key] ?? TrafficVolume()
            lines.append("\(key),\(volume.received),\(volume.sent)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

enum TrafficByteFormat {
    /// Short, monospaced-friendly rendering: 999 B, 12.4 kB, 3.21 GB.
    static func string(_ bytes: UInt64) -> String {
        let units = ["B", "kB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        return String(format: value >= 100 ? "%.0f %@" : "%.2f %@", value, units[unit])
    }
}
