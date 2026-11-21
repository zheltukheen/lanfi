import XCTest

final class SurveyHeatmapTests: XCTestCase {
    func testRequestBuildsGridFromSamples() {
        let sample = SurveySample(
            id: UUID(), x: 0.5, y: 0.5, rssi: -50, ssid: "Office",
            bssid: "AA:BB:CC:DD:EE:01", recordedAt: Date())
        let request = SurveyHeatmapRequest(
            columns: 2, rows: 2, cellSize: 50, pixelWidth: 100, pixelHeight: 100,
            samples: [sample], walls: [], obstacles: [], accessPoints: [],
            predictiveMode: false, planWidthMeters: 30, planHeightMeters: 30)

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
                predictiveMode: false, planWidthMeters: 30, planHeightMeters: 30)
        }

        XCTAssertNotEqual(request(rssi: -50).key, request(rssi: -70).key)
    }

    func testStreamYieldsPartialGridsBeforeCompletion() async {
        let sample = SurveySample(
            id: UUID(), x: 0.5, y: 0.5, rssi: -50, ssid: "Office",
            bssid: "AA:BB:CC:DD:EE:01", recordedAt: Date())
        let request = SurveyHeatmapRequest(
            columns: 2, rows: 3, cellSize: 50, pixelWidth: 100, pixelHeight: 150,
            samples: [sample], walls: [], obstacles: [], accessPoints: [],
            predictiveMode: false, planWidthMeters: 30, planHeightMeters: 30)

        var grids: [HeatGridCache.Grid] = []
        for await grid in request.stream(chunkRows: 1) {
            grids.append(grid)
        }

        XCTAssertGreaterThanOrEqual(grids.count, 2)
        XCTAssertEqual(grids.last?.cells.compactMap { $0 }.count, 6)
        XCTAssertEqual(grids.first?.cells.compactMap { $0 }.count, 2)
    }

    func testPredictiveRequestUsesAccessPoint() {
        let ap = SurveyAccessPoint.new(x: 0.5, y: 0.5, band: "5GHz", channel: 36, txPowerDbm: 20)
        let request = SurveyHeatmapRequest(
            columns: 2, rows: 2, cellSize: 50, pixelWidth: 100, pixelHeight: 100,
            samples: [], walls: [], obstacles: [], accessPoints: [ap],
            predictiveMode: true, planWidthMeters: 30, planHeightMeters: 30)

        let grid = request.build()
        XCTAssertEqual(grid.cells.compactMap { $0 }.count, 4)
    }

    /// A plan stretched across a wide pane covers fewer metres vertically than
    /// horizontally. Using the width for both axes made the predicted distance
    /// too long and painted weak coverage over a room that is actually close.
    func testPredictorUsesSeparateHorizontalAndVerticalScales() {
        let ap = SurveyAccessPoint.new(x: 0.5, y: 0.5, band: "5GHz", channel: 36, txPowerDbm: 20)
        let square = SurveyPredictor.estimate(
            x: 0.5, y: 1.0, accessPoints: [ap], walls: [], obstacles: [],
            planWidthMeters: 30, planHeightMeters: 30)
        let stretched = SurveyPredictor.estimate(
            x: 0.5, y: 1.0, accessPoints: [ap], walls: [], obstacles: [],
            planWidthMeters: 30, planHeightMeters: 6)
        XCTAssertNotNil(square)
        XCTAssertNotNil(stretched)
        XCTAssertGreaterThan(stretched ?? 0, square ?? 0)
    }
}
