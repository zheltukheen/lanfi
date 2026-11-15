import XCTest

final class SurveyHeatmapTests: XCTestCase {
    func testRequestBuildsGridFromSamples() {
        let sample = SurveySample(
            id: UUID(), x: 0.5, y: 0.5, rssi: -50, ssid: "Office",
            bssid: "AA:BB:CC:DD:EE:01", recordedAt: Date())
        let request = SurveyHeatmapRequest(
            columns: 2, rows: 2, cellSize: 50, pixelWidth: 100, pixelHeight: 100,
            samples: [sample], walls: [], obstacles: [], accessPoints: [],
            predictiveMode: false, planWidthMeters: 30)

        let grid = request.build()
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.rows, 2)
        XCTAssertEqual(grid.cells.count, 4)
        XCTAssertNotNil(grid.cells[0])
    }

    func testKeyChangesWhenSampleRSSIChanges() {
        func request(rssi: Int) -> SurveyHeatmapRequest {
            let sample = SurveySample(
                id: UUID(), x: 0.5, y: 0.5, rssi: rssi, ssid: "Office",
                bssid: "AA:BB:CC:DD:EE:01", recordedAt: Date())
            return SurveyHeatmapRequest(
                columns: 2, rows: 2, cellSize: 50, pixelWidth: 100, pixelHeight: 100,
                samples: [sample], walls: [], obstacles: [], accessPoints: [],
                predictiveMode: false, planWidthMeters: 30)
        }

        XCTAssertNotEqual(request(rssi: -50).key, request(rssi: -70).key)
    }

    func testPredictiveRequestUsesAccessPoint() {
        let ap = SurveyAccessPoint.new(x: 0.5, y: 0.5, band: "5GHz", channel: 36, txPowerDbm: 20)
        let request = SurveyHeatmapRequest(
            columns: 2, rows: 2, cellSize: 50, pixelWidth: 100, pixelHeight: 100,
            samples: [], walls: [], obstacles: [], accessPoints: [ap],
            predictiveMode: true, planWidthMeters: 30)

        let grid = request.build()
        XCTAssertEqual(grid.cells.compactMap { $0 }.count, 4)
    }
}
