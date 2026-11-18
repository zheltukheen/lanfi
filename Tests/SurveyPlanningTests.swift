import XCTest

final class SurveyPlanningTests: XCTestCase {
    func testFreeSpaceRadiusNarrowsWithHigherTarget() {
        let easy = SurveyPlanRequest(widthMeters: 20, heightMeters: 12, targetRSSI: -75)
        let hard = SurveyPlanRequest(widthMeters: 20, heightMeters: 12, targetRSSI: -55)
        XCTAssertGreaterThan(
            SurveyPlanner.freeSpaceRadiusMeters(easy),
            SurveyPlanner.freeSpaceRadiusMeters(hard))
    }

    func testPlanScalesAccessPointCountWithArea() {
        let small = SurveyPlanner.plan(
            SurveyPlanRequest(widthMeters: 10, heightMeters: 8, targetRSSI: -65))
        let large = SurveyPlanner.plan(
            SurveyPlanRequest(widthMeters: 40, heightMeters: 30, targetRSSI: -65))
        XCTAssertGreaterThanOrEqual(large.accessPointCount, small.accessPointCount)
        XCTAssertTrue((0...1).contains(small.accessPoints[0].x))
        XCTAssertTrue((0...1).contains(small.accessPoints[0].y))
        XCTAssertGreaterThan(small.estimatedCoveragePercent, 0)
        XCTAssertLessThanOrEqual(large.estimatedCoveragePercent, 100)
    }

    func testActiveSurveyFindsGapsAndNextTarget() {
        var project = SurveyProject.new(name: "Plan")
        project.planWidthMeters = 12
        project.planHeightMeters = 9
        let empty = ActiveSurveyAdvisor.evaluate(project: project)
        XCTAssertEqual(empty.nextTarget, empty.gaps.first)
        XCTAssertGreaterThan(empty.requiredSamples, 0)
        XCTAssertFalse(empty.isComplete)

        project.samples = (0..<20).map { index in
            SurveySample(
                id: UUID(), x: Double(index % 5) / 5, y: Double(index / 5) / 4,
                rssi: -60, ssid: "Office", bssid: "aa", recordedAt: Date())
        }
        let covered = ActiveSurveyAdvisor.evaluate(project: project)
        XCTAssertGreaterThanOrEqual(covered.coveragePercent, empty.coveragePercent)
        XCTAssertEqual(covered.collectedSamples, 20)
        XCTAssertEqual(covered.averageRSSI, -60)
    }
}
