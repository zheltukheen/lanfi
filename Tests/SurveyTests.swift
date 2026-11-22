import XCTest

final class SurveyTests: XCTestCase {
    func testSurveyRoundTripWithFloorPlanData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-survey-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SurveyStore(directory: directory)
        var project = SurveyProject.new(name: "Office")
        project.imageFileName = "floorplan.png"
        project.samples = [
            SurveySample(
                id: UUID(), x: 0.25, y: 0.5, rssi: -55, ssid: "Office",
                bssid: "00:1A:2B:11:22:33", recordedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        let image = Data([0x89, 0x50, 0x4E, 0x47])
        store.save(project, imageData: image)

        let latest = try XCTUnwrap(store.latestProject())
        XCTAssertEqual(latest.name, "Office")
        XCTAssertEqual(latest.samples.count, 1)
        XCTAssertEqual(latest.samples.first?.rssi, -55)
        XCTAssertEqual(store.imageData(for: latest), image)
    }

    func testCutoutContainsOnlyItsInterior() {
        let cutout = SurveyCutout.new(points: [
            SurveyPoint(x: 0.2, y: 0.2), SurveyPoint(x: 0.4, y: 0.2),
            SurveyPoint(x: 0.4, y: 0.4), SurveyPoint(x: 0.2, y: 0.4),
        ])
        XCTAssertTrue(cutout.contains(x: 0.3, y: 0.3))
        XCTAssertFalse(cutout.contains(x: 0.1, y: 0.3))
        XCTAssertFalse(cutout.contains(x: 0.5, y: 0.3))
        XCTAssertFalse(SurveyCutout.new(points: []).contains(x: 0.3, y: 0.3))
    }

    func testProjectDecodesWithoutCutouts() throws {
        var project = SurveyProject.new(name: "No cutouts")
        project.imageFileName = nil
        let encoded = try JSONEncoder().encode(project)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "cutouts")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SurveyProject.self, from: old)
        XCTAssertTrue(decoded.cutouts.isEmpty)
    }

    func testSampleDecodesWithoutPointMeasurement() throws {
        let json = """
            {"id":"\(UUID().uuidString)","x":0.2,"y":0.3,"rssi":-61,"ssid":"Office",
             "bssid":"00:1A:2B:11:22:33","recordedAt":0}
            """
        let sample = try JSONDecoder().decode(SurveySample.self, from: Data(json.utf8))
        XCTAssertNil(sample.downloadMbps)
        XCTAssertNil(sample.latencyMilliseconds)
        XCTAssertNil(sample.measuredAt)
    }

    func testSampleCarriesPointMeasurement() throws {
        let sample = SurveySample(
            id: UUID(), x: 0.2, y: 0.3, rssi: -61, ssid: "Office",
            bssid: "00:1A:2B:11:22:33", recordedAt: Date(timeIntervalSince1970: 1),
            downloadMbps: 420, latencyMilliseconds: 8.5, measuredAt: Date(timeIntervalSince1970: 2))
        let decoded = try JSONDecoder().decode(
            SurveySample.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(decoded.downloadMbps, 420)
        XCTAssertEqual(decoded.latencyMilliseconds, 8.5)
        XCTAssertNotNil(decoded.measuredAt)
    }

    func testNewProjectStartsEmpty() {
        let project = SurveyProject.new()
        XCTAssertTrue(project.samples.isEmpty)
        XCTAssertNil(project.imageFileName)
        XCTAssertFalse(project.name.isEmpty)
    }
}
