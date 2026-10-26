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

    func testNewProjectStartsEmpty() {
        let project = SurveyProject.new()
        XCTAssertTrue(project.samples.isEmpty)
        XCTAssertNil(project.imageFileName)
        XCTAssertFalse(project.name.isEmpty)
    }
}
