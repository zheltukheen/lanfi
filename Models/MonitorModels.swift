import Foundation
import LanFiCore

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
    case deauthBurst
    case roamingFailure
    /// P3.7: the gateway's MAC changed while its IP stayed the same.
    case gatewayChanged
    /// P3.7: the system resolver disagreed with a public resolver.
    case dnsMismatch
    /// P3.4: a tunnel that was up is gone.
    case vpnDropped
    /// P3.4: DNS or IPv6 appears to bypass the tunnel.
    case vpnLeak
    /// G6: a BSSID that was not in the environment baseline appeared.
    case newAccessPoint

    var title: String {
        switch self {
        case .connected: return String(localized: "Connected")
        case .disconnected: return String(localized: "Disconnected")
        case .roamed: return String(localized: "Roamed")
        case .channelChanged: return String(localized: "Channel changed")
        case .securityChanged: return String(localized: "Security changed")
        case .weakSignal: return String(localized: "Weak signal")
        case .deauthBurst: return String(localized: "Deauth burst")
        case .roamingFailure: return String(localized: "Roaming failure")
        case .gatewayChanged: return String(localized: "Gateway MAC changed")
        case .dnsMismatch: return String(localized: "DNS answer mismatch")
        case .vpnDropped: return String(localized: "VPN dropped")
        case .vpnLeak: return String(localized: "Possible VPN leak")
        case .newAccessPoint: return String(localized: "New access point")
        }
    }
}

extension MonitorEventKind {
    /// The kinds that cost reliability. A successful roam, a connection and a
    /// new neighbour are neutral, so they never move the score.
    var reliabilitySignal: ReliabilitySignal? {
        switch self {
        case .disconnected: return .disconnected
        case .roamingFailure: return .roamingFailure
        case .weakSignal: return .weakSignal
        case .deauthBurst: return .deauthBurst
        case .securityChanged: return .securityChanged
        case .channelChanged: return .channelChanged
        case .gatewayChanged: return .gatewayChanged
        case .dnsMismatch: return .dnsMismatch
        case .vpnDropped: return .vpnDropped
        case .vpnLeak: return .vpnLeak
        case .connected, .roamed, .newAccessPoint: return nil
        }
    }
}

extension ReliabilitySignal {
    var title: String {
        switch self {
        case .disconnected: return String(localized: "Disconnections")
        case .roamingFailure: return String(localized: "Roaming failures")
        case .weakSignal: return String(localized: "Weak-signal transitions")
        case .deauthBurst: return String(localized: "Deauth bursts")
        case .securityChanged: return String(localized: "Security changes")
        case .channelChanged: return String(localized: "Channel changes")
        case .gatewayChanged: return String(localized: "Gateway MAC changes")
        case .dnsMismatch: return String(localized: "DNS mismatches")
        case .vpnDropped: return String(localized: "VPN drops")
        case .vpnLeak: return String(localized: "Possible VPN leaks")
        }
    }
}

extension ReliabilityGrade {
    var title: String {
        switch self {
        case .good: return String(localized: "Good")
        case .fair: return String(localized: "Fair")
        case .poor: return String(localized: "Poor")
        case .insufficient: return String(localized: "Not enough data")
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
    let pmfRequired: Bool?
    let wpsEnabled: Bool?

    init(network: NetworkModel) {
        bssid = network.bssid
        ssid = network.displaySSID
        channel = network.channel
        security = network.security
        securityScore = NetworkAnalyzer.securityScore(for: network)
        rssi = network.signal
        pmfRequired = network.pmfRequired
        wpsEnabled = network.wpsEnabled
    }
}

/// Per-BSSID aggregate for every network seen during a monitor sample.
/// Raw samples are kept only for the connected link; peers are cheap enough to
/// keep for every visible AP without growing the store linearly with time.
struct MonitorPeer: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let bssid: String
    var ssid: String
    var band: String
    var channel: Int
    var security: String
    var rssiMin: Int
    var rssiMax: Int
    var rssiSum: Int
    var samples: Int
    var lastSeen: Date

    var averageRSSI: Int {
        guard samples > 0 else { return 0 }
        return Int((Double(rssiSum) / Double(samples)).rounded())
    }

    init(network: NetworkModel, at: Date) {
        id = network.id
        bssid = network.bssid
        ssid = network.displaySSID
        band = network.band.label
        channel = network.channel
        security = network.security
        rssiMin = network.signal
        rssiMax = network.signal
        rssiSum = network.signal
        samples = 1
        lastSeen = at
    }

    mutating func observe(_ network: NetworkModel, at: Date) {
        ssid = network.displaySSID
        band = network.band.label
        channel = network.channel
        security = network.security
        rssiMin = min(rssiMin, network.signal)
        rssiMax = max(rssiMax, network.signal)
        rssiSum += network.signal
        samples += 1
        lastSeen = at
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
    var peers: [String: MonitorPeer] = [:]
    var state: MonitorLinkState?
    var lastSampleAt: Date?

    static let empty = MonitorSnapshot()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case samples, events, peers, state, lastSampleAt
    }

    /// Tolerates monitor files written before `peers` and PMF/WPS were added.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        samples = try container.decodeIfPresent([MonitorSample].self, forKey: .samples) ?? []
        events = try container.decodeIfPresent([MonitorEvent].self, forKey: .events) ?? []
        peers = try container.decodeIfPresent([String: MonitorPeer].self, forKey: .peers) ?? [:]
        state = try container.decodeIfPresent(MonitorLinkState.self, forKey: .state)
        lastSampleAt = try container.decodeIfPresent(Date.self, forKey: .lastSampleAt)
    }

    var statistics: HistoryStatistics? {
        HistoryStatistics(values: samples.map(\.rssi))
    }

    /// Returns true when a sample or event was added and the snapshot needs to
    /// be written to disk.
    @discardableResult
    mutating func ingest(
        connected: NetworkModel?, visible: [NetworkModel] = [], now: Date,
        sampleInterval: TimeInterval
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
                if current.rssi <= -80 || current.rssi < previous.rssi - 10 {
                    appendEvent(
                        .roamingFailure, at: now, bssid: current.bssid, ssid: current.ssid,
                        detail:
                            "Roamed to a weaker link: \(current.rssi) dBm, was \(previous.rssi) dBm"
                    )
                }
                changed = true
            } else if previous.channel != current.channel {
                appendEvent(
                    .channelChanged, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: "Channel \(previous.channel) → \(current.channel)")
                changed = true
            }

            var securityReasons: [String] = []
            if current.securityScore < previous.securityScore {
                securityReasons.append("\(previous.security) → \(current.security)")
            }
            if previous.pmfRequired == true, current.pmfRequired != true {
                securityReasons.append("PMF no longer required")
            }
            if previous.wpsEnabled != true, current.wpsEnabled == true {
                securityReasons.append("WPS enabled")
            }
            if !securityReasons.isEmpty {
                appendEvent(
                    .securityChanged, at: now, bssid: current.bssid, ssid: current.ssid,
                    detail: securityReasons.joined(separator: " · "))
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
            let observed = visible.isEmpty ? [connected] : visible
            for network in observed {
                if var peer = peers[network.id] {
                    peer.observe(network, at: now)
                    peers[network.id] = peer
                } else {
                    peers[network.id] = MonitorPeer(network: network, at: now)
                }
            }
            changed = true
        }

        return changed
    }

    /// Folds capture-only findings into the same event stream as live scans.
    @discardableResult
    mutating func ingestCapture(
        _ report: CaptureSecurityReport, at fallback: Date = Date()
    ) -> Bool {
        var changed = false
        for counter in report.management where counter.burst {
            let at = counter.lastSeen ?? fallback
            let ssid =
                peers.values.first {
                    $0.bssid.caseInsensitiveCompare(counter.bssid) == .orderedSame
                }?.ssid ?? ""
            appendEvent(
                .deauthBurst, at: at, bssid: counter.bssid, ssid: ssid,
                detail: "\(counter.disruptionCount) deauth/disassoc frames in a burst")
            changed = true
        }
        return changed
    }

    /// Folds an event produced outside the scan loop (gateway/DNS guard) into
    /// the same stream, so the Monitor log and alert rules apply unchanged.
    @discardableResult
    mutating func ingest(event: MonitorEvent) -> Bool {
        events.append(event)
        if events.count > 500 {
            events.removeFirst(events.count - 500)
        }
        return true
    }

    mutating func trim(
        retention: TimeInterval, now: Date, maximumSamples: Int = 20_000,
        maximumEvents: Int = 500
    ) {
        let cutoff = now.addingTimeInterval(-retention)
        samples = Array(samples.filter { $0.at >= cutoff }.suffix(max(1, maximumSamples)))
        events = Array(events.filter { $0.at >= cutoff }.suffix(max(1, maximumEvents)))
        peers = peers.filter { $0.value.lastSeen >= cutoff }
        if peers.count > 500 {
            let keep = peers.sorted { $0.value.lastSeen > $1.value.lastSeen }.prefix(500)
            peers = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
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

struct MonitorComparison: Equatable {
    let currentAverage: Int?
    let previousAverage: Int?
    let currentSamples: Int
    let previousSamples: Int

    var delta: Int? {
        guard let currentAverage, let previousAverage else { return nil }
        return currentAverage - previousAverage
    }

    init(samples: [MonitorSample], window: TimeInterval, now: Date = Date()) {
        let currentStart = now.addingTimeInterval(-window)
        let previousStart = currentStart.addingTimeInterval(-window)
        let current = samples.filter { $0.at >= currentStart && $0.at <= now }
        let previous = samples.filter { $0.at >= previousStart && $0.at < currentStart }
        currentSamples = current.count
        previousSamples = previous.count
        currentAverage = Self.average(current)
        previousAverage = Self.average(previous)
    }

    private static func average(_ samples: [MonitorSample]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let total = samples.reduce(0) { $0 + $1.rssi }
        return Int((Double(total) / Double(samples.count)).rounded())
    }
}

enum MonitorCSV {
    static func make(peers: [MonitorPeer]) -> String {
        var lines = ["bssid,ssid,band,channel,security,samples,rssi_min,rssi_max,rssi_avg,last_seen"]
        let formatter = ISO8601DateFormatter()
        for peer in peers {
            lines.append(
                [
                    escape(peer.bssid),
                    escape(peer.ssid),
                    escape(peer.band),
                    String(peer.channel),
                    escape(peer.security),
                    String(peer.samples),
                    String(peer.rssiMin),
                    String(peer.rssiMax),
                    String(peer.averageRSSI),
                    formatter.string(from: peer.lastSeen),
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

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
