import XCTest

final class SpeedTestHistoryTests: XCTestCase {

    func testScheduleDueLogic() {
        let now = Date()
        XCTAssertFalse(SpeedTestSchedule.off.isDue(lastRun: nil, now: now))
        XCTAssertTrue(SpeedTestSchedule.hourly.isDue(lastRun: nil, now: now))
        XCTAssertTrue(
            SpeedTestSchedule.hourly.isDue(
                lastRun: now.addingTimeInterval(-3601), now: now))
        XCTAssertFalse(
            SpeedTestSchedule.hourly.isDue(
                lastRun: now.addingTimeInterval(-3599), now: now))
        XCTAssertTrue(
            SpeedTestSchedule.daily.isDue(
                lastRun: now.addingTimeInterval(-24 * 3600 - 1), now: now))
    }

    func testNextRun() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(
            SpeedTestSchedule.hourly.nextRun(after: last)!,
            last.addingTimeInterval(3600))
        XCTAssertNil(SpeedTestSchedule.off.nextRun(after: last))
    }

    func testStoreRoundTripTrimsToLimit() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-speed-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ThroughputHistoryStore(directory: directory, limit: 2)
        let reports = (0..<3).map { index in
            ThroughputMeasurement(
                report: ThroughputReport(
                    downloadMbps: Double(index),
                    uploadMbps: 10,
                    latencyMilliseconds: 5,
                    responsiveness: 500,
                    testedAt: Date(timeIntervalSince1970: 1_000 + Double(index))
                ))
        }
        store.save(reports)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.testedAt), reports.suffix(2).map(\.testedAt))

        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testMeasurementGrade() {
        let measurement = ThroughputMeasurement(
            report: ThroughputReport(
                downloadMbps: 100,
                uploadMbps: 20,
                latencyMilliseconds: 10,
                responsiveness: 1_200,
                testedAt: Date()
            ))
        XCTAssertEqual(measurement.bufferbloatGrade, "A")
    }
}
