import Foundation

/// An event that can cost the link reliability. The app maps its monitor
/// events onto this smaller vocabulary so the score is computed in the package
/// and can be tested without the monitor.
public enum ReliabilitySignal: String, CaseIterable, Codable, Sendable {
    case disconnected
    case roamingFailure
    case weakSignal
    case deauthBurst
    case securityChanged
    case channelChanged
    case gatewayChanged
    case dnsMismatch
    case vpnDropped
    case vpnLeak
}

public struct ReliabilitySignalRecord: Equatable, Sendable {
    public let signal: ReliabilitySignal
    public let at: Date

    public init(signal: ReliabilitySignal, at: Date) {
        self.signal = signal
        self.at = at
    }
}

public struct ReliabilitySample: Equatable, Sendable {
    public let at: Date
    public let rssi: Int

    public init(at: Date, rssi: Int) {
        self.at = at
        self.rssi = rssi
    }
}

public enum ReliabilityGrade: String, Equatable, Sendable {
    /// Too little history to judge either way; not the same as "bad".
    case insufficient
    case good
    case fair
    case poor
}

/// One repeated problem with the time range it happened in.
public struct ReliabilityProblem: Equatable, Identifiable, Sendable {
    public let signal: ReliabilitySignal
    public let count: Int
    public let firstAt: Date
    public let lastAt: Date

    public init(signal: ReliabilitySignal, count: Int, firstAt: Date, lastAt: Date) {
        self.signal = signal
        self.count = count
        self.firstAt = firstAt
        self.lastAt = lastAt
    }

    public var id: String { signal.rawValue }
}

public struct ReliabilityAssessment: Equatable, Sendable {
    /// Nil when the history is too sparse to score.
    public let score: Int?
    public let grade: ReliabilityGrade
    public let sampleCount: Int
    public let observedSeconds: TimeInterval
    public let averageRSSI: Int?
    public let weakSampleShare: Double
    public let problems: [ReliabilityProblem]
    public let startedAt: Date?
    public let endedAt: Date?

    public init(
        score: Int?, grade: ReliabilityGrade, sampleCount: Int, observedSeconds: TimeInterval,
        averageRSSI: Int?, weakSampleShare: Double, problems: [ReliabilityProblem],
        startedAt: Date?, endedAt: Date?
    ) {
        self.score = score
        self.grade = grade
        self.sampleCount = sampleCount
        self.observedSeconds = observedSeconds
        self.averageRSSI = averageRSSI
        self.weakSampleShare = weakSampleShare
        self.problems = problems
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public static let empty = ReliabilityAssessment(
        score: nil, grade: .insufficient, sampleCount: 0, observedSeconds: 0, averageRSSI: nil,
        weakSampleShare: 0, problems: [], startedAt: nil, endedAt: nil)

    public var isInsufficient: Bool { grade == .insufficient }
}

/// Scores the last stretch of the monitor history.
///
/// The score starts at 100 and loses points for disconnects, failed roams,
/// deauth bursts, security/gateway/DNS/VPN events, channel changes and time
/// spent at a weak signal. Every category is capped, so one storm cannot drive
/// the score to zero on its own, and the thresholds for "not enough data" are
/// explicit rather than a low score in disguise.
public enum ReliabilityAssessor {
    /// Ten samples and five minutes: below this a verdict would describe the
    /// sampling rate, not the network.
    public static let minimumSamples = 10
    public static let minimumObservation: TimeInterval = 5 * 60

    public static func assess(
        samples: [ReliabilitySample], signals: [ReliabilitySignalRecord]
    ) -> ReliabilityAssessment {
        let ordered = samples.sorted { $0.at < $1.at }
        guard let first = ordered.first, let last = ordered.last else {
            return .empty
        }
        let observed = last.at.timeIntervalSince(first.at)
        let average = Int(
            (Double(ordered.reduce(0) { $0 + $1.rssi }) / Double(ordered.count)).rounded())
        let weak = ordered.filter { $0.rssi <= -75 }.count
        let weakShare = Double(weak) / Double(ordered.count)
        let problems = problemList(signals)
        let enough = ordered.count >= minimumSamples && observed >= minimumObservation

        guard enough else {
            return ReliabilityAssessment(
                score: nil, grade: .insufficient, sampleCount: ordered.count,
                observedSeconds: observed, averageRSSI: average, weakSampleShare: weakShare,
                problems: problems, startedAt: first.at, endedAt: last.at)
        }

        var score = 100
        for problem in problems {
            let weight = weights(for: problem.signal)
            score -= min(problem.count * weight.each, weight.cap)
        }
        score -= min(25, Int((weakShare * 25).rounded()))
        score = max(0, min(100, score))

        let grade: ReliabilityGrade
        switch score {
        case 85...: grade = .good
        case 60..<85: grade = .fair
        default: grade = .poor
        }

        return ReliabilityAssessment(
            score: score, grade: grade, sampleCount: ordered.count, observedSeconds: observed,
            averageRSSI: average, weakSampleShare: weakShare, problems: problems,
            startedAt: first.at, endedAt: last.at)
    }

    /// One row per signal, ordered by how much it can cost the score.
    static func problemList(_ signals: [ReliabilitySignalRecord]) -> [ReliabilityProblem] {
        var grouped: [ReliabilitySignal: [Date]] = [:]
        for record in signals {
            grouped[record.signal, default: []].append(record.at)
        }
        return grouped.compactMap { signal, dates -> ReliabilityProblem? in
            guard let first = dates.min(), let last = dates.max() else { return nil }
            return ReliabilityProblem(
                signal: signal, count: dates.count, firstAt: first, lastAt: last)
        }.sorted { lhs, rhs in
            let left = weights(for: lhs.signal)
            let right = weights(for: rhs.signal)
            let leftCost = min(lhs.count * left.each, left.cap)
            let rightCost = min(rhs.count * right.each, right.cap)
            if leftCost != rightCost { return leftCost > rightCost }
            return lhs.signal.rawValue < rhs.signal.rawValue
        }
    }

    static func weights(for signal: ReliabilitySignal) -> (each: Int, cap: Int) {
        switch signal {
        case .disconnected: return (12, 40)
        case .roamingFailure: return (10, 30)
        case .gatewayChanged: return (8, 16)
        case .deauthBurst: return (6, 18)
        case .vpnDropped: return (6, 12)
        case .securityChanged: return (5, 15)
        case .vpnLeak: return (5, 15)
        case .dnsMismatch: return (4, 12)
        case .weakSignal: return (3, 12)
        case .channelChanged: return (1, 5)
        }
    }
}
