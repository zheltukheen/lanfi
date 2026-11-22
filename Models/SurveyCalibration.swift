import Foundation

/// Offset between what the predictive model says and what the walk actually
/// measured. Applying it turns a generic path-loss estimate into one tuned for
/// this building without changing the AP layout.
struct SurveyCalibration: Equatable {
    /// Median of (measured − predicted). Negative means the model is optimistic.
    let offsetDb: Double
    let sampleCount: Int
    /// Median absolute error left after applying the offset.
    let residualDb: Double

    var summary: String {
        String(
            format: String(localized: "Calibration %+.0f dB · %lld points · ±%.0f dB"),
            offsetDb, sampleCount, residualDb)
    }
}

enum SurveyCalibrationCalculator {
    static func compute(project: SurveyProject) -> SurveyCalibration? {
        guard !project.accessPoints.isEmpty, !project.samples.isEmpty else { return nil }
        let width = project.planWidthMeters ?? 30
        let height = project.planHeightMeters ?? width
        var errors: [Double] = []
        errors.reserveCapacity(project.samples.count)
        for sample in project.samples {
            guard
                let predicted = SurveyPredictor.estimate(
                    x: sample.x, y: sample.y, accessPoints: project.accessPoints,
                    walls: project.walls, obstacles: project.obstacles,
                    planWidthMeters: width, planHeightMeters: height)
            else { continue }
            errors.append(Double(sample.rssi - predicted))
        }
        guard errors.count >= 3 else { return nil }
        let offset = median(errors)
        let residual = median(errors.map { abs($0 - offset) })
        return SurveyCalibration(
            offsetDb: (offset * 10).rounded() / 10,
            sampleCount: errors.count,
            residualDb: (residual * 10).rounded() / 10
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let ordered = values.sorted()
        guard !ordered.isEmpty else { return 0 }
        let middle = ordered.count / 2
        if ordered.count.isMultiple(of: 2) {
            return (ordered[middle - 1] + ordered[middle]) / 2
        }
        return ordered[middle]
    }
}
