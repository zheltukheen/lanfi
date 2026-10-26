import XCTest

final class SurveyInterpolatorTests: XCTestCase {
    func testSingleSampleReturnsItsRSSI() {
        let sample = makeSample(x: 0.5, y: 0.5, rssi: -55)
        XCTAssertEqual(
            SurveyInterpolator.estimate(x: 0.2, y: 0.2, samples: [sample], walls: []),
            -55
        )
    }

    func testInterpolationSitsBetweenNeighbourSamples() throws {
        let left = makeSample(x: 0.2, y: 0.5, rssi: -40)
        let right = makeSample(x: 0.8, y: 0.5, rssi: -80)
        let value = try XCTUnwrap(
            SurveyInterpolator.estimate(x: 0.5, y: 0.5, samples: [left, right], walls: [])
        )
        XCTAssertGreaterThan(value, -80)
        XCTAssertLessThan(value, -40)
    }

    func testWallAttenuationLowersEstimate() throws {
        let sample = makeSample(x: 0.2, y: 0.5, rssi: -40)
        let wall = SurveyWall.new(x1: 0.5, y1: 0.0, x2: 0.5, y2: 1.0)
        let clear = try XCTUnwrap(
            SurveyInterpolator.estimate(x: 0.8, y: 0.5, samples: [sample], walls: [])
        )
        let blocked = try XCTUnwrap(
            SurveyInterpolator.estimate(x: 0.8, y: 0.5, samples: [sample], walls: [wall])
        )
        XCTAssertLessThan(blocked, clear)
    }

    func testSegmentIntersection() {
        XCTAssertTrue(
            SurveyInterpolator.segmentsIntersect(
                x1: 0, y1: 0.5, x2: 1, y2: 0.5, x3: 0.5, y3: 0, x4: 0.5, y4: 1
            )
        )
        XCTAssertFalse(
            SurveyInterpolator.segmentsIntersect(
                x1: 0, y1: 0.2, x2: 1, y2: 0.2, x3: 0.5, y3: 0.4, x4: 0.5, y4: 1
            )
        )
    }

    private func makeSample(x: Double, y: Double, rssi: Int) -> SurveySample {
        SurveySample(
            id: UUID(), x: x, y: y, rssi: rssi, ssid: "Test", bssid: "AA:BB:CC:DD:EE:FF",
            recordedAt: Date()
        )
    }
}
