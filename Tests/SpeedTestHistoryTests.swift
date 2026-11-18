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

    func testLegacyMeasurementWithoutNetworkStillDecodes() throws {
        let measurement = ThroughputMeasurement(
            report: ThroughputReport(
                downloadMbps: 100,
                uploadMbps: 20,
                latencyMilliseconds: 10,
                responsiveness: 1_200,
                testedAt: Date(timeIntervalSince1970: 1_000)),
            network: SpeedTestNetwork(ssid: "Office", bssid: "AA:BB:CC:DD:EE:FF"))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(measurement))
                as? [String: Any])
        object.removeValue(forKey: "network")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(ThroughputMeasurement.self, from: legacy)
        XCTAssertNil(decoded.network)
        XCTAssertEqual(decoded.report.downloadMbps, 100)
    }

    func testStoreRoundTripKeepsNetwork() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-speed-network-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let network = SpeedTestNetwork(ssid: "Home", bssid: "11:22:33:44:55:66")
        let store = ThroughputHistoryStore(directory: directory)
        store.save([measurement(down: 90, network: network)])

        XCTAssertEqual(store.load().first?.network, network)
    }

    func testGroupsAreNewestFirstAndKeepOneEntryPerSSID() {
        let office = SpeedTestNetwork(ssid: "Office", bssid: "AA:AA:AA:AA:AA:AA")
        let officeOtherRadio = SpeedTestNetwork(ssid: "Office", bssid: "BB:BB:BB:BB:BB:BB")
        let home = SpeedTestNetwork(ssid: "Home", bssid: "CC:CC:CC:CC:CC:CC")
        let now = Date(timeIntervalSince1970: 10_000)

        let groups = SpeedTestHistoryIndex.groups([
            measurement(down: 100, at: now.addingTimeInterval(-3_600), network: office),
            measurement(down: 200, at: now, network: officeOtherRadio),
            measurement(down: 50, at: now.addingTimeInterval(-7_200), network: home),
            measurement(down: 999, at: now, network: nil),
        ])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.network.displayName, "Office")
        XCTAssertEqual(groups.first?.testCount, 2)
        XCTAssertEqual(groups.first?.latest?.report.downloadMbps, 200)
        XCTAssertEqual(groups.first?.averageDownloadMbps, 150)
        XCTAssertEqual(groups.first?.downloadDeltaMbps, 100)
    }

    func testFilteringByNetworkReturnsNewestFirst() {
        let network = SpeedTestNetwork(ssid: "Office", bssid: nil)
        let other = SpeedTestNetwork(ssid: "Home", bssid: nil)
        let now = Date(timeIntervalSince1970: 10_000)
        let history = [
            measurement(down: 10, at: now.addingTimeInterval(-60), network: network),
            measurement(down: 20, at: now, network: network),
            measurement(down: 30, at: now, network: other),
        ]

        let filtered = SpeedTestHistoryIndex.measurements(history, for: network.key)
        XCTAssertEqual(filtered.map { $0.report.downloadMbps }, [20, 10])
        XCTAssertEqual(
            SpeedTestHistoryIndex.measurements(history, for: nil).count, 3)
    }

    private func measurement(
        down: Double, at date: Date = Date(), network: SpeedTestNetwork?
    ) -> ThroughputMeasurement {
        ThroughputMeasurement(
            report: ThroughputReport(
                downloadMbps: down,
                uploadMbps: 10,
                latencyMilliseconds: 5,
                responsiveness: 500,
                testedAt: date),
            network: network)
    }
}
