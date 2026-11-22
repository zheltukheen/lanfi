import XCTest

final class SurveyFloorComparisonTests: XCTestCase {
    private func sample(_ rssi: Int) -> SurveySample {
        SurveySample(
            id: UUID(), x: 0.5, y: 0.5, rssi: rssi, ssid: "Office",
            bssid: "AA:BB:CC:DD:EE:FF", recordedAt: Date())
    }

    func testComparisonReportsMeasuredPredictedAndDelta() throws {
        var ground = SurveyProject.new(name: "Ground")
        ground.planWidthMeters = 20
        ground.planHeightMeters = 20
        ground.accessPoints = [SurveyAccessPoint.new(x: 0.5, y: 0.5)]
        ground.samples = [sample(-60), sample(-50)]

        var first = SurveyProject.new(name: "First")
        first.floorLevel = 1
        first.planWidthMeters = 20
        first.planHeightMeters = 20

        let comparisons = SurveyFloorComparator.compare(floors: [ground, first])
        XCTAssertEqual(comparisons.count, 2)
        XCTAssertEqual(comparisons[0].measuredAverage, -55)
        XCTAssertEqual(comparisons[0].sampleCount, 2)
        let predicted = try XCTUnwrap(comparisons[0].predictedAverage)
        XCTAssertEqual(comparisons[0].delta, -55 - predicted)
        XCTAssertNil(comparisons[1].measuredAverage)
        XCTAssertNotNil(comparisons[1].predictedAverage)
        XCTAssertNil(comparisons[1].delta)
    }

    func testComparisonWithoutAccessPointsHasNoPrediction() {
        var floor = SurveyProject.new(name: "Empty")
        floor.samples = [sample(-70)]
        let comparison = SurveyFloorComparator.compare(floors: [floor]).first
        XCTAssertEqual(comparison?.measuredAverage, -70)
        XCTAssertNil(comparison?.predictedAverage)
        XCTAssertNil(comparison?.delta)
    }

    func testFloorLossChangesThePrediction() throws {
        var ground = SurveyProject.new(name: "Ground")
        ground.planWidthMeters = 20
        ground.planHeightMeters = 20
        ground.accessPoints = [SurveyAccessPoint.new(x: 0.5, y: 0.5)]
        var upper = SurveyProject.new(name: "Upper")
        upper.floorLevel = 1
        upper.planWidthMeters = 20
        upper.planHeightMeters = 20
        let floors = [ground, upper]

        let lowLoss = try XCTUnwrap(
            SurveyFloorComparator.compare(floors: floors, floorAttenuationDb: 0)
                .last?.predictedAverage)
        let highLoss = try XCTUnwrap(
            SurveyFloorComparator.compare(floors: floors, floorAttenuationDb: 25)
                .last?.predictedAverage)
        XCTAssertGreaterThan(lowLoss, highLoss)
    }
}
