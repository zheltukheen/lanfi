import Foundation

/// Measured versus predicted coverage for one floor. The 3D view uses this to
/// show which floor the model gets wrong, instead of only drawing each floor in
/// isolation.
struct SurveyFloorComparison: Identifiable, Equatable {
    let floorName: String
    let floorLevel: Int
    let sampleCount: Int
    let measuredAverage: Int?
    let predictedAverage: Int?

    var id: String { "\(floorLevel)-\(floorName)" }

    /// Positive means reality is stronger than the model.
    var delta: Int? {
        guard let measuredAverage, let predictedAverage else { return nil }
        return measuredAverage - predictedAverage
    }
}

enum SurveyFloorComparator {
    static let gridSteps = 8

    static func compare(
        floors: [SurveyProject], floorAttenuationDb: Double = 12
    ) -> [SurveyFloorComparison] {
        let inputs = floors.map {
            SurveyFloorInput(
                floorLevel: $0.floorLevel,
                floorHeightMeters: $0.floorHeightMeters,
                walls: $0.walls,
                obstacles: $0.obstacles,
                accessPoints: $0.accessPoints,
                cutouts: $0.cutouts
            )
        }
        return floors.map { floor in
            let samples = floor.samples.map(\.rssi)
            let measured =
                samples.isEmpty
                ? nil : Int((Double(samples.reduce(0, +)) / Double(samples.count)).rounded())
            let predicted = predictedAverage(
                for: floor, inputs: inputs, floorAttenuationDb: floorAttenuationDb)
            return SurveyFloorComparison(
                floorName: floor.name,
                floorLevel: floor.floorLevel,
                sampleCount: samples.count,
                measuredAverage: measured,
                predictedAverage: predicted
            )
        }
    }

    private static func predictedAverage(
        for floor: SurveyProject, inputs: [SurveyFloorInput], floorAttenuationDb: Double
    ) -> Int? {
        guard inputs.contains(where: { !$0.accessPoints.isEmpty }) else { return nil }
        var values: [Int] = []
        values.reserveCapacity(gridSteps * gridSteps)
        for row in 0..<gridSteps {
            for column in 0..<gridSteps {
                let x = (Double(column) + 0.5) / Double(gridSteps)
                let y = (Double(row) + 0.5) / Double(gridSteps)
                if let rssi = SurveyPredictor.estimate3D(
                    x: x, y: y, targetFloorLevel: floor.floorLevel, floors: inputs,
                    planWidthMeters: floor.planWidthMeters ?? 30,
                    floorAttenuationDb: floorAttenuationDb)
                {
                    values.append(rssi)
                }
            }
        }
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
