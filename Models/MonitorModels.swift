import Foundation

enum MonitorRetention: String, CaseIterable, Identifiable, Codable, Hashable {
    case hour
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: return String(localized: "1 hour")
        case .day: return String(localized: "24 hours")
        case .week: return String(localized: "7 days")
        case .month: return String(localized: "30 days")
        }
    }

    var interval: TimeInterval {
        switch self {
        case .hour: return 60 * 60
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        }
    }

    /// More history means a slower sample rate so the store stays small.
    var sampleInterval: TimeInterval {
        switch self {
        case .hour: return 15
        case .day: return 60
        case .week: return 5 * 60
        case .month: return 15 * 60
        }
    }
}

enum MonitorEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case connected
    case disconnected
    case roamed
    case channelChanged
    case securityChanged
    case weakSignal

    var title: String {
        switch self {
        case .connected: return String(localized: "Connected")
        case .disconnected: return String(localized: "Disconnected")
        case .roamed: return String(localized: "Roamed")
        case .channelChanged: return String(localized: "Channel changed")
        case .securityChanged: return String(localized: "Security changed")
        case .weakSignal: return String(localized: "Weak signal")
        }
    }
}

struct MonitorSample: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let at: Date
    let bssid: String
    let ssid: String
    let rssi: Int
    let snr: Int?
    let channel: Int
    let band: String
    let utilization: Int?
    let security: String

    init(id: UUID = UUID(), network: NetworkModel, at: Date) {
        self.id = id
        self.at = at
        bssid = network.bssid
        ssid = network.displaySSID
        rssi = network.signal
        snr = network.snr
        channel = network.channel
        band = network.band.label
        utilization = network.channelUtilization
        security = network.security
    }
}

struct MonitorEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let at: Date
    let kind: MonitorEventKind
    let bssid: String
    let ssid: String
    let detail: String

    init(
        id: UUID = UUID(), at: Date, kind: MonitorEventKind, bssid: String, ssid: String,
        detail: String
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.bssid = bssid
        self.ssid = ssid
        self.detail = detail
    }
}

struct MonitorLinkState: Codable, Equatable, Sendable {
    let bssid: String
    let ssid: String
    let channel: Int
    let security: String
    let securityScore: Int
    let rssi: Int

    init(network: NetworkModel) {
        bssid = network.bssid
        ssid = network.displaySSID
        channel = network.channel
        security = network.security
        securityScore = NetworkAnalyzer.securityScore(for: network)
        rssi = network.signal
    }
}

/// Append-only rolling history of the connected Wi-Fi link.
///
/// Samples are throttled by `sampleInterval`; events are emitted on every
/// transition so a short channel change or security downgrade is not lost
/// between two samples.
struct MonitorSnapshot: Codable, Equatable {
    var samples: [MonitorSample] = []
    var events: [MonitorEvent] = []
    var state: MonitorLinkState?
    var lastSampleAt: Date?

    static let empty = MonitorSnapshot()

    var statistics: HistoryStatistics? {
        HistoryStatistics(values: samples.map(\.rssi))
    }

    /// Returns true when a sample or event was added and the snapshot needs to
    /// be written to disk.
    @discardableResult
    mutating func ingest(
        connected: NetworkModel?, now: Date, sampleInterval: TimeInterval
    ) -> Bool {
        guard let connected else {
            guard let previous = state else { return false }
            state = nil
            appendEvent(
                .disconnected, at: now, bssid: previous.bssid, ssid: previous.ssid,
                detail: "Lost connection to \(previous.ssid)")
            return true
        }

        let current = MonitorLinkState(network: connected)
        var changed = false

        if let previous = state {
            if previous.bssid != current.bssid {
                appendEvent(
                    .roamed, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: "\(previous.bssid) → \(current.bssid)")
                changed = true
            } else if previous.channel != current.channel {
                appendEvent(
                    .channelChanged, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: "Channel \(previous.channel) → \(current.channel)")
                changed = true
            }

            if current.securityScore < previous.securityScore {
                appendEvent(
                    .securityChanged, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: "\(previous.security) → \(current.security)")
                changed = true
            }

            if current.rssi <= -75, previous.rssi > -75 {
                appendEvent(
                    .weakSignal, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: "RSSI \(current.rssi) dBm")
                changed = true
            }
        } else {
            appendEvent(
                .connected, at: now, bssid: current.bssid, ssid: current.ssid,
                detail: "Connected on channel \(current.channel)")
            changed = true
        }

        state = current

        if lastSampleAt == nil
            || now.timeIntervalSince(lastSampleAt ?? .distantPast) >= sampleInterval
        {
            samples.append(MonitorSample(network: connected, at: now))
            lastSampleAt = now
            changed = true
        }

        return changed
    }

    mutating func trim(
        retention: TimeInterval, now: Date, maximumSamples: Int = 20_000,
        maximumEvents: Int = 500
    ) {
        let cutoff = now.addingTimeInterval(-retention)
        samples = Array(samples.filter { $0.at >= cutoff }.suffix(max(1, maximumSamples)))
        events = Array(events.filter { $0.at >= cutoff }.suffix(max(1, maximumEvents)))
        if let lastSampleAt, lastSampleAt < cutoff {
            self.lastSampleAt = nil
            state = nil
        }
    }

    private mutating func appendEvent(
        _ kind: MonitorEventKind, at: Date, bssid: String, ssid: String, detail: String
    ) {
        events.append(
            MonitorEvent(at: at, kind: kind, bssid: bssid, ssid: ssid, detail: detail))
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }
    }
}

enum MonitorCSV {
    static func make(samples: [MonitorSample]) -> String {
        var lines = ["timestamp,bssid,ssid,rssi,snr,channel,band,utilization,security"]
        let formatter = ISO8601DateFormatter()
        for sample in samples {
            lines.append(
                [
                    formatter.string(from: sample.at),
                    escape(sample.bssid),
                    escape(sample.ssid),
                    String(sample.rssi),
                    sample.snr.map(String.init) ?? "",
                    String(sample.channel),
                    escape(sample.band),
                    sample.utilization.map(String.init) ?? "",
                    escape(sample.security),
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
