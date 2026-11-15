import Foundation

struct MonitorAlertSettings: Codable, Equatable {
    var weakSignal: Bool = true
    var disconnect: Bool = true
    var roam: Bool = false
    var channelChange: Bool = false
    var securityChange: Bool = true

    var quietHoursEnabled: Bool = false
    var quietStartHour: Int = 22
    var quietEndHour: Int = 7
    var cooldownMinutes: Int = 5

    static let `default` = MonitorAlertSettings()

    var anyEnabled: Bool {
        weakSignal || disconnect || roam || channelChange || securityChange
    }

    func isEnabled(for kind: MonitorEventKind) -> Bool {
        switch kind {
        case .weakSignal: return weakSignal
        case .disconnected: return disconnect
        case .roamed: return roam
        case .channelChanged: return channelChange
        case .securityChanged: return securityChange
        case .connected: return false
        }
    }

    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let start = max(0, min(23, quietStartHour))
        let end = max(0, min(23, quietEndHour))
        guard start != end else { return false }

        let hour = calendar.component(.hour, from: date)
        if start < end {
            return hour >= start && hour < end
        }
        return hour >= start || hour < end
    }
}

/// Decides whether an event should turn into a notification. Cooldown is per
/// event kind so a flapping signal cannot flood Notification Center.
struct MonitorAlertPolicy {
    private var lastSent: [MonitorEventKind: Date] = [:]

    mutating func shouldNotify(
        event: MonitorEvent, settings: MonitorAlertSettings, now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard settings.isEnabled(for: event.kind) else { return false }
        guard !settings.isQuiet(at: now, calendar: calendar) else { return false }

        let cooldown = TimeInterval(max(0, settings.cooldownMinutes)) * 60
        if let last = lastSent[event.kind], now.timeIntervalSince(last) < cooldown {
            return false
        }

        lastSent[event.kind] = now
        return true
    }
}
