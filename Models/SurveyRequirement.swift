import Foundation
import LanFiCore

// The requirement value and its report live in LanFiCore. The validator stays
// here because survey points have not moved yet.
typealias SurveyRequirement = LanFiCore.SurveyRequirement
typealias SurveyValidationReport = LanFiCore.SurveyValidationReport

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
        return regions[best / 3][best % 3]
    }
}
