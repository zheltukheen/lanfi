import Foundation

/// G9: the pass/fail profile a survey is judged against. Off by default so a
/// report never invents a requirement the user did not choose.
///
/// Only values a survey point actually carries can be judged: RSSI always, and
/// download/latency when the point was measured. Noise and SNR are not recorded
/// per point, so they are deliberately absent rather than guessed.
public struct SurveyRequirement: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isEnabled: Bool
    public var minRSSI: Int
    /// Nil means "do not judge throughput"; a point without a measurement is
    /// counted as unmeasured, never as a failure.
    public var minThroughputMbps: Double?
    public var maxLatencyMilliseconds: Double?

    public init(
        id: UUID = UUID(), isEnabled: Bool = false, minRSSI: Int = -67,
        minThroughputMbps: Double? = nil, maxLatencyMilliseconds: Double? = nil
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.minRSSI = minRSSI
        self.minThroughputMbps = minThroughputMbps
        self.maxLatencyMilliseconds = maxLatencyMilliseconds
    }

    public static let off = SurveyRequirement()

    public var judgesThroughput: Bool { minThroughputMbps != nil }
    public var judgesLatency: Bool { maxLatencyMilliseconds != nil }

    /// "RSSI ≥ -67 dBm · ≥ 50 Mbps · ≤ 60 ms"
    public var summary: String {
        var parts = [String(format: "RSSI ≥ %lld dBm", minRSSI)]
        if let minThroughputMbps {
            parts.append(String(format: "≥ %.0f Mbps", minThroughputMbps))
        }
        if let maxLatencyMilliseconds {
            parts.append(String(format: "≤ %.0f ms", maxLatencyMilliseconds))
        }
        return parts.joined(separator: " · ")
    }
}

public struct SurveyValidationReport: Equatable, Sendable {
    public struct Failure: Identifiable, Equatable, Sendable {
        public let sampleID: UUID
        public let x: Double
        public let y: Double
        public let rssi: Int
        public let reasons: [String]

        public init(sampleID: UUID, x: Double, y: Double, rssi: Int, reasons: [String]) {
            self.sampleID = sampleID
            self.x = x
            self.y = y
            self.rssi = rssi
            self.reasons = reasons
        }

        public var id: UUID { sampleID }
        public var detail: String { reasons.joined(separator: ", ") }
    }

    public let requirement: SurveyRequirement
    public let evaluated: Int
    public let failures: [Failure]
    /// Points that had no throughput/latency measurement; they are excluded
    /// from that criterion instead of being marked failed.
    public let unmeasuredThroughput: Int
    public let unmeasuredLatency: Int
    /// The worst third of the plan, e.g. "south-east area".
    public let worstRegion: String?

    public init(
        requirement: SurveyRequirement, evaluated: Int, failures: [Failure],
        unmeasuredThroughput: Int, unmeasuredLatency: Int, worstRegion: String?
    ) {
        self.requirement = requirement
        self.evaluated = evaluated
        self.failures = failures
        self.unmeasuredThroughput = unmeasuredThroughput
        self.unmeasuredLatency = unmeasuredLatency
        self.worstRegion = worstRegion
    }

    public var passed: Int { evaluated - failures.count }

    public var passPercentage: Double {
        guard evaluated > 0 else { return 0 }
        return Double(passed) / Double(evaluated) * 100
    }

    public var isPassing: Bool { evaluated > 0 && failures.isEmpty }

    /// "PASS · 87% (13 of 100 points fail)"
    public var verdict: String {
        guard evaluated > 0 else { return String(localized: "No points to judge") }
        let percent = String(format: "%.0f%%", passPercentage)
        if failures.isEmpty {
            return String(
                format: String(localized: "PASS · %@ (%lld points)"), percent, evaluated)
        }
        return String(
            format: String(localized: "FAIL · %@ · %lld of %lld points fail"), percent,
            failures.count, evaluated)
    }

    /// One line for the report: verdict plus the worst area.
    public var reportLine: String {
        var line = verdict
        if let worstRegion {
            line += " · " + String(format: String(localized: "worst: %@"), worstRegion)
        }
        if unmeasuredThroughput > 0 || unmeasuredLatency > 0 {
            line +=
                " · "
                + String(
                    format: String(localized: "%lld points without throughput/latency measurement"),
                    max(unmeasuredThroughput, unmeasuredLatency))
        }
        return line
    }
}
