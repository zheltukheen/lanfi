import Foundation

// MARK: - Samples

/// One hop in one continuous-monitor round. `latencyMilliseconds` is nil when
/// the router did not answer this round, which is what the heatmap draws as a
/// missed reply.
struct RouteHopSample: Equatable, Sendable {
    let hop: Int
    let address: String?
    let latencyMilliseconds: Double?

    var didReply: Bool { address != nil }
}

/// One round of the route monitor: the whole path as it looked at one moment.
struct RouteSample: Identifiable, Equatable, Sendable {
    let id: UUID
    let at: Date
    let hops: [RouteHopSample]

    init(id: UUID = UUID(), at: Date, hops: [RouteHopSample]) {
        self.id = id
        self.at = at
        self.hops = hops
    }

    var destination: RouteHopSample? { hops.last }
    var destinationLatencyMilliseconds: Double? { hops.last?.latencyMilliseconds }
    var destinationReached: Bool { hops.last?.didReply == true }

    func hop(_ ttl: Int) -> RouteHopSample? {
        hops.first { $0.hop == ttl }
    }

    /// `MTRService` with one round per call is the transport: each report is one
    /// sample, so the rolling window is a list of reports rather than a second
    /// probing engine.
    static func make(from report: MTRReport, at date: Date = Date()) -> RouteSample {
        let hops = report.hops.map { hop in
            RouteHopSample(
                hop: hop.hop,
                address: hop.address,
                latencyMilliseconds: hop.lastMilliseconds)
        }
        return RouteSample(at: date, hops: hops)
    }
}

// MARK: - Rolling statistics

struct RouteHopStat: Identifiable, Equatable, Sendable {
    let hop: Int
    let address: String?
    let attempts: Int
    let replies: Int
    let averageMilliseconds: Double?
    let worstMilliseconds: Double?

    var id: Int { hop }

    var lossPercent: Double {
        guard attempts > 0 else { return 0 }
        return Double(attempts - replies) / Double(attempts) * 100
    }
}

enum RouteHopStatistics {
    /// Loss over the whole window, not per round: a single missed reply is a
    /// 100 % loss in a one-round sample, which would make every timeout look
    /// like a dead hop.
    static func compute(samples: [RouteSample]) -> [RouteHopStat] {
        var attempts: [Int: Int] = [:]
        var replies: [Int: Int] = [:]
        var addresses: [Int: String] = [:]
        var latencies: [Int: [Double]] = [:]

        for sample in samples {
            for hop in sample.hops {
                attempts[hop.hop, default: 0] += 1
                if let address = hop.address {
                    replies[hop.hop, default: 0] += 1
                    addresses[hop.hop] = address
                }
                if let latency = hop.latencyMilliseconds {
                    latencies[hop.hop, default: []].append(latency)
                }
            }
        }

        return attempts.keys.sorted().map { ttl in
            let values = latencies[ttl] ?? []
            return RouteHopStat(
                hop: ttl,
                address: addresses[ttl],
                attempts: attempts[ttl] ?? 0,
                replies: replies[ttl] ?? 0,
                averageMilliseconds: values.isEmpty
                    ? nil : values.reduce(0, +) / Double(values.count),
                worstMilliseconds: values.max())
        }
    }
}

// MARK: - Route change

struct RoutePath: Equatable, Sendable {
    /// TTL → address. Hops that did not answer are not part of the path, so a
    /// transient timeout does not read as a route change on its own.
    let hops: [Int: String]

    init(hops: [Int: String]) {
        self.hops = hops
    }

    init(sample: RouteSample) {
        var map: [Int: String] = [:]
        for hop in sample.hops {
            if let address = hop.address { map[hop.hop] = address }
        }
        hops = map
    }

    var isEmpty: Bool { hops.isEmpty }
}

struct RouteHopChange: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case added
        case removed
        case changed
    }

    let hop: Int
    let from: String?
    let to: String?

    var kind: Kind {
        if from == nil { return .added }
        if to == nil { return .removed }
        return .changed
    }

    var summary: String {
        switch kind {
        case .added:
            return String(format: String(localized: "Hop %lld added: %@"), hop, to ?? "*")
        case .removed:
            return String(format: String(localized: "Hop %lld removed: %@"), hop, from ?? "*")
        case .changed:
            return String(
                format: String(localized: "Hop %lld: %@ → %@"), hop, from ?? "*", to ?? "*")
        }
    }
}

struct RouteChange: Identifiable, Equatable, Sendable {
    let id: UUID
    let at: Date
    let changes: [RouteHopChange]

    init(id: UUID = UUID(), at: Date, changes: [RouteHopChange]) {
        self.id = id
        self.at = at
        self.changes = changes
    }

    var summary: String { changes.map(\.summary).joined(separator: "; ") }
}

/// Edge-triggered route detection with a flap guard: a new path has to appear
/// twice in a row before it is announced, so one timed-out hop does not produce
/// an event and then another when it answers again.
struct RouteChangeDetector: Sendable {
    static let confirmationsRequired = 2

    private(set) var confirmed: RoutePath?
    private var candidate: RoutePath?
    private var candidateCount = 0

    mutating func observe(_ path: RoutePath, at date: Date) -> RouteChange? {
        guard !path.isEmpty else { return nil }
        if let confirmed, confirmed == path {
            candidate = nil
            candidateCount = 0
            return nil
        }
        if candidate == path {
            candidateCount += 1
        } else {
            candidate = path
            candidateCount = 1
        }

        guard let baseline = confirmed else {
            confirmed = path
            candidate = nil
            candidateCount = 0
            return nil
        }
        guard candidateCount >= Self.confirmationsRequired else { return nil }

        confirmed = path
        candidate = nil
        candidateCount = 0
        let changes = Self.diff(from: baseline, to: path)
        return changes.isEmpty ? nil : RouteChange(at: date, changes: changes)
    }

    mutating func reset() {
        confirmed = nil
        candidate = nil
        candidateCount = 0
    }

    static func diff(from old: RoutePath, to new: RoutePath) -> [RouteHopChange] {
        let ttlValues = Set(old.hops.keys).union(new.hops.keys).sorted()
        return ttlValues.compactMap { ttl in
            let from = old.hops[ttl]
            let to = new.hops[ttl]
            guard from != to else { return nil }
            return RouteHopChange(hop: ttl, from: from, to: to)
        }
    }
}

// MARK: - Thresholds

struct RouteMonitorSettings: Codable, Equatable, Sendable {
    static let latencyRange: ClosedRange<Double> = 20...1000
    static let lossRange: ClosedRange<Double> = 5...100

    var latencyThresholdMilliseconds: Double = 120
    var lossThresholdPercent: Double = 25
    var notifyOnRouteChange = true
    var notifyOnThreshold = true

    var normalized: RouteMonitorSettings {
        var copy = self
        copy.latencyThresholdMilliseconds = min(
            max(copy.latencyThresholdMilliseconds, Self.latencyRange.lowerBound),
            Self.latencyRange.upperBound)
        copy.lossThresholdPercent = min(
            max(copy.lossThresholdPercent, Self.lossRange.lowerBound),
            Self.lossRange.upperBound)
        return copy
    }
}

struct RouteThresholdCrossing: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case latency
        case loss
    }

    let id: UUID
    let hop: Int
    let address: String?
    let kind: Kind
    let value: Double

    init(
        id: UUID = UUID(), hop: Int, address: String?, kind: Kind, value: Double
    ) {
        self.id = id
        self.hop = hop
        self.address = address
        self.kind = kind
        self.value = value
    }

    var summary: String {
        let host = address ?? "*"
        switch kind {
        case .latency:
            return String(
                format: String(localized: "Hop %lld is slow: %@ over %lld ms"),
                hop, host, Int(value.rounded()))
        case .loss:
            return String(
                format: String(localized: "Hop %lld is losing replies: %@ at %lld%% loss"),
                hop, host, Int(value.rounded()))
        }
    }
}

/// Reports a hop once when it crosses a threshold and again only after it has
/// recovered, so a permanently slow hop does not notify on every round.
struct RouteThresholdTracker: Sendable {
    static let minimumAttempts = 3

    private var slowHops: Set<Int> = []
    private var lossyHops: Set<Int> = []

    mutating func evaluate(
        stats: [RouteHopStat], settings: RouteMonitorSettings
    ) -> [RouteThresholdCrossing] {
        var crossings: [RouteThresholdCrossing] = []
        var nextSlow: Set<Int> = []
        var nextLossy: Set<Int> = []

        for stat in stats where stat.attempts >= Self.minimumAttempts {
            if let average = stat.averageMilliseconds,
                average > settings.latencyThresholdMilliseconds
            {
                nextSlow.insert(stat.hop)
                if !slowHops.contains(stat.hop) {
                    crossings.append(
                        RouteThresholdCrossing(
                            hop: stat.hop, address: stat.address, kind: .latency, value: average))
                }
            }
            if stat.lossPercent >= settings.lossThresholdPercent {
                nextLossy.insert(stat.hop)
                if !lossyHops.contains(stat.hop) {
                    crossings.append(
                        RouteThresholdCrossing(
                            hop: stat.hop, address: stat.address, kind: .loss,
                            value: stat.lossPercent))
                }
            }
        }

        slowHops = nextSlow
        lossyHops = nextLossy
        return crossings
    }

    mutating func reset() {
        slowHops = []
        lossyHops = []
    }
}

// MARK: - Cadence

enum RouteMonitorCadence {
    static let activeInterval: TimeInterval = 10
    static let panelClosedInterval: TimeInterval = 30
    static let backgroundInterval: TimeInterval = 60

    /// One round every 10 s while the screen is open, 30 s while it is closed
    /// and 60 s while LanFi is in the background. A round is one probe per hop,
    /// so even the active cadence stays below one round per second.
    static func interval(isApplicationActive: Bool, isPanelVisible: Bool) -> TimeInterval {
        guard isApplicationActive else { return backgroundInterval }
        return isPanelVisible ? activeInterval : panelClosedInterval
    }
}
