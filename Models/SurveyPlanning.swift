import Foundation

/// P1.4 Survey Planning 2.0: suggests an access-point layout for a plan and
/// estimates its coverage before anyone walks the floor.
struct SurveyPlanRequest: Equatable {
    var widthMeters: Double = 20
    var heightMeters: Double = 12
    var targetRSSI: Int = -65
    var txPowerDbm: Double = 20
    var band: String = "5GHz"
    var channel: Int = 36

    var areaSquareMeters: Double { max(1, widthMeters * heightMeters) }

    var frequencyMHz: Double {
        if band.contains("2.4") { return 2400 + Double(channel) * 5 }
        if band.contains("6") { return 5950 + Double(channel) * 5 }
        return 5000 + Double(channel) * 5
    }
}

struct SurveyPlanResult: Equatable {
    let accessPoints: [SurveyPoint]
    let radiusMeters: Double
    let spacingMeters: Double
    let estimatedCoveragePercent: Double
    let notes: [String]

    var accessPointCount: Int { accessPoints.count }
}

enum SurveyPlanner {
    /// Distance at which free-space path loss brings the signal down to the
    /// target RSSI. Walls and furniture shorten it; the estimate is optimistic.
    static func freeSpaceRadiusMeters(_ request: SurveyPlanRequest) -> Double {
        let allowedLoss = request.txPowerDbm - Double(request.targetRSSI)
        let frequency = max(100, request.frequencyMHz)
        let exponent = (allowedLoss - 20 * log10(frequency) + 27.55) / 20
        return min(80, max(2, pow(10, exponent)))
    }

    static func plan(_ request: SurveyPlanRequest) -> SurveyPlanResult {
        let radius = freeSpaceRadiusMeters(request)
        let width = max(1, request.widthMeters)
        let height = max(1, request.heightMeters)
        // Overlap neighbouring cells so coverage does not drop between APs.
        let spacing = max(4, radius * 1.45)
        let columns = max(1, Int(ceil(width / spacing)))
        let rows = max(1, Int(ceil(height / spacing)))
        let effectiveColumns = max(1, columns)
        let effectiveRows = max(1, rows)

        var points: [SurveyPoint] = []
        for row in 0..<effectiveRows {
            for column in 0..<effectiveColumns {
                points.append(
                    SurveyPoint(
                        x: (Double(column) + 0.5) / Double(effectiveColumns),
                        y: (Double(row) + 0.5) / Double(effectiveRows)
                    ))
            }
        }

        // Fraction of a metre grid that falls inside at least one AP circle,
        // clipped to the plan. Walls are not modelled here.
        var covered = 0
        var total = 0
        let steps = 24
        for row in 0..<steps {
            for column in 0..<steps {
                let x = (Double(column) + 0.5) / Double(steps) * width
                let y = (Double(row) + 0.5) / Double(steps) * height
                total += 1
                let inside = points.contains { point in
                    let dx = point.x * width - x
                    let dy = point.y * height - y
                    return hypot(dx, dy) <= radius
                }
                if inside { covered += 1 }
            }
        }
        let coverage = total == 0 ? 0 : Double(covered) / Double(total) * 100

        var notes: [String] = [
            String(
                format: String(localized: "Free-space radius %.1f m at %d dBm target."),
                radius, request.targetRSSI),
            String(localized: "Walls, floors and furniture reduce coverage; add walls to refine."),
        ]
        if coverage < 90 {
            notes.append(String(localized: "Coverage is below 90%; add an AP or lower the target."))
        }
        if radius > 35 {
            notes.append(
                String(localized: "A single AP reaches far at this target — verify with a walk-through."))
        }

        return SurveyPlanResult(
            accessPoints: points,
            radiusMeters: radius,
            spacingMeters: spacing,
            estimatedCoveragePercent: min(100, coverage),
            notes: notes
        )
    }
}

/// Active Survey: how much of the plan has been walked, where the gaps are and
/// where to take the next sample.
struct ActiveSurveyProgress: Equatable {
    let requiredSamples: Int
    let collectedSamples: Int
    let coveredCells: Int
    let totalCells: Int
    let coveragePercent: Double
    let gaps: [SurveyPoint]
    let nextTarget: SurveyPoint?
    let weakestRSSI: Int?
    let averageRSSI: Int?

    var isComplete: Bool { gaps.isEmpty && collectedSamples >= requiredSamples }
}

enum ActiveSurveyAdvisor {
    static func evaluate(
        project: SurveyProject, targetRSSI: Int = -65, cellMeters: Double = 3
    ) -> ActiveSurveyProgress {
        let width = project.planWidthMeters ?? 12
        let height = project.planHeightMeters ?? max(4, width * 0.7)
        let columns = max(2, Int(ceil(width / max(1, cellMeters))))
        let rows = max(2, Int(ceil(height / max(1, cellMeters))))
        let total = columns * rows

        var covered = Set<Int>()
        for sample in project.samples {
            let column = min(columns - 1, max(0, Int(sample.x * Double(columns))))
            let row = min(rows - 1, max(0, Int(sample.y * Double(rows))))
            covered.insert(row * columns + column)
        }

        var gaps: [SurveyPoint] = []
        for row in 0..<rows {
            for column in 0..<columns where !covered.contains(row * columns + column) {
                gaps.append(
                    SurveyPoint(
                        x: (Double(column) + 0.5) / Double(columns),
                        y: (Double(row) + 0.5) / Double(rows)))
            }
        }

        let rssiValues = project.samples.map(\.rssi)
        return ActiveSurveyProgress(
            requiredSamples: total,
            collectedSamples: project.samples.count,
            coveredCells: covered.count,
            totalCells: total,
            coveragePercent: total == 0 ? 0 : Double(covered.count) / Double(total) * 100,
            gaps: gaps,
            nextTarget: gaps.first,
            weakestRSSI: rssiValues.min(),
            averageRSSI: rssiValues.isEmpty ? nil : rssiValues.reduce(0, +) / rssiValues.count
        )
    }
}
