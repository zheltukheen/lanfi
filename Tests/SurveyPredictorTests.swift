import XCTest

final class SurveyPredictorTests: XCTestCase {
    func testPredictionFallsWithDistance() throws {
        let ap = SurveyAccessPoint.new(x: 0.2, y: 0.5)
        let near = try XCTUnwrap(SurveyPredictor.estimate(x: 0.3, y: 0.5, accessPoints: [ap], walls: [], obstacles: []))
        let far = try XCTUnwrap(SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: []))
        XCTAssertGreaterThan(near, far)
    }

    func testWallReducesPrediction() throws {
        let ap = SurveyAccessPoint.new(x: 0.2, y: 0.5)
        let wall = SurveyWall.new(x1: 0.5, y1: 0, x2: 0.5, y2: 1)
        let clear = try XCTUnwrap(
            SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: [])
        )
        let blocked = try XCTUnwrap(
            SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [wall], obstacles: [])
        )
        XCTAssertLessThan(blocked, clear)
    }
}
