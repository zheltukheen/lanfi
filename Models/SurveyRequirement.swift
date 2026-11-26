import Foundation

/// G9: the pass/fail profile a survey is judged against. Off by default so a
/// report never invents a requirement the user did not choose.
///
/// Only values a survey point actually carries can be judged: RSSI always, and
/// download/latency when the point was measured. Noise and SNR are not recorded
/// per point, so they are deliberately absent rather than guessed.
struct SurveyRequirement: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var isEnabled: Bool = false
    var minRSSI: Int = -67
    /// Nil means "do not judge throughput"; a point without a measurement is
    /// counted as unmeasured, never as a failure.
    var minThroughputMbps: Double? = nil
    var maxLatencyMilliseconds: Double? = nil

    static let off = SurveyRequirement()

    var judgesThroughput: Bool { minThroughputMbps != nil }
    var judgesLatency: Bool { maxLatencyMilliseconds != nil }

    /// "RSSI ≥ -67 dBm · ≥ 50 Mbps · ≤ 60 ms"
    var summary: String {
        var parts = [String(format: String(localized: "RSSI ≥ %lld dBm"), minRSSI)]
        if let minThroughputMbps {
            parts.append(String(format: String(localized: "≥ %.0f Mbps"), minThroughputMbps))
        }
        if let maxLatencyMilliseconds {
            parts.append(String(format: String(localized: "≤ %.0f ms"), maxLatencyMilliseconds))
        }
        return parts.joined(separator: " · ")
    }
}

struct SurveyValidationReport: Equatable {
    struct Failure: Identifiable, Equatable {
        let sampleID: UUID
        let x: Double
        let y: Double
        let rssi: Int
        let reasons: [String]

        var id: UUID { sampleID }
        var detail: String { reasons.joined(separator: ", ") }
    }

    let requirement: SurveyRequirement
    let evaluated: Int
    let failures: [Failure]
    /// Points that had no throughput/latency measurement; they are excluded
    /// from that criterion instead of being marked failed.
    let unmeasuredThroughput: Int
    let unmeasuredLatency: Int
    /// The worst third of the plan, e.g. "south-east area".
    let worstRegion: String?

    var passed: Int { evaluated - failures.count }

    var passPercentage: Double {
        guard evaluated > 0 else { return 0 }
        return Double(passed) / Double(evaluated) * 100
    }

    var isPassing: Bool { evaluated > 0 && failures.isEmpty }

    /// "PASS · 87% (13 of 100 points fail)"
    var verdict: String {
        guard evaluated > 0 else { return String(localized: "No points to judge") }
        let percent = String(format: "%.0f%%", passPercentage)
        if failures.isEmpty {
            return String(format: String(localized: "PASS · %@ (%lld points)"), percent, evaluated)
        }
        return String(
            format: String(localized: "FAIL · %@ · %lld of %lld points fail"), percent,
            failures.count, evaluated)
    }

    /// One line for the report: verdict plus the worst area.
    var reportLine: String {
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

enum SurveyValidator {
    private static let regions = [
        ["north-west area", "north area", "north-east area"],
        ["west area", "centre", "east area"],
        ["south-west area", "south area", "south-east area"],
    ]

    /// Nil when the requirement is off: no profile, no verdict.
    static func evaluate(
        samples: [SurveySample], requirement: SurveyRequirement
    ) -> SurveyValidationReport? {
        guard requirement.isEnabled else { return nil }

        var failures: [SurveyValidationReport.Failure] = []
        var unmeasuredThroughput = 0
        var unmeasuredLatency = 0

        for sample in samples {
            var reasons: [String] = []
            if sample.rssi < requirement.minRSSI {
                reasons.append(
                    String(
                        format: String(localized: "RSSI %lld < %lld dBm"), sample.rssi,
                        requirement.minRSSI))
            }
            if let minThroughput = requirement.minThroughputMbps {
                if let download = sample.downloadMbps {
                    if download < minThroughput {
                        reasons.append(
                            String(
                                format: String(localized: "%.0f < %.0f Mbps"), download,
                                minThroughput))
                    }
                } else {
                    unmeasuredThroughput += 1
                }
            }
            if let maxLatency = requirement.maxLatencyMilliseconds {
                if let latency = sample.latencyMilliseconds {
                    if latency > maxLatency {
                        reasons.append(
                            String(
                                format: String(localized: "%.0f > %.0f ms"), latency, maxLatency))
                    }
                } else {
                    unmeasuredLatency += 1
                }
            }
            guard !reasons.isEmpty else { continue }
            failures.append(
                SurveyValidationReport.Failure(
                    sampleID: sample.id, x: sample.x, y: sample.y, rssi: sample.rssi,
                    reasons: reasons))
        }

        return SurveyValidationReport(
            requirement: requirement,
            evaluated: samples.count,
            failures: failures,
            unmeasuredThroughput: unmeasuredThroughput,
            unmeasuredLatency: unmeasuredLatency,
            worstRegion: worstRegion(for: failures))
    }

    /// Buckets failures into a 3×3 grid and names the fullest bucket, so the
    /// report points at an area instead of a list of coordinates.
    private static func worstRegion(for failures: [SurveyValidationReport.Failure]) -> String? {
        guard !failures.isEmpty else { return nil }
        var counts = [Int](repeating: 0, count: 9)
        for failure in failures {
            let column = min(max(Int(failure.x * 3), 0), 2)
            let row = min(max(Int(failure.y * 3), 0), 2)
            counts[row * 3 + column] += 1
        }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }) else { return nil }
        return String(localized: String.LocalizationValue(regions[best / 3][best % 3]))
    }
}
