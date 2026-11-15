import XCTest

final class NetworkHistoryTests: XCTestCase {
    func testStatisticsForKnownValues() throws {
        let statistics = try XCTUnwrap(HistoryStatistics(values: [-80, -70, -60, -50]))
        XCTAssertEqual(statistics.count, 4)
        XCTAssertEqual(statistics.minimum, -80)
        XCTAssertEqual(statistics.maximum, -50)
        XCTAssertEqual(statistics.average, -65, accuracy: 0.001)
        XCTAssertEqual(statistics.averageRounded, -65)
        XCTAssertEqual(statistics.p95, -50)
    }

    func testStatisticsP95UsesNearestRank() throws {
        let statistics = try XCTUnwrap(HistoryStatistics(values: Array(1...20)))
        XCTAssertEqual(statistics.p95, 19)
        XCTAssertEqual(statistics.averageRounded, 11)
    }

    func testStatisticsForEmptyValuesIsNil() {
        XCTAssertNil(HistoryStatistics(values: []))
    }

    func testRecordAppendsAllSeriesAndTrimsToLimit() {
        var history = NetworkHistory()
        history.record(makeNetwork(id: "a", signal: -50, noise: -90, snr: 40, utilization: 10), maxPoints: 2)
        history.record(makeNetwork(id: "a", signal: -60, noise: -88, snr: 28, utilization: 20), maxPoints: 2)
        history.record(makeNetwork(id: "a", signal: -70, noise: -85, snr: 15, utilization: 30), maxPoints: 2)

        XCTAssertEqual(history.signal["a"], [-60, -70])
        XCTAssertEqual(history.noise["a"], [-88, -85])
        XCTAssertEqual(history.snr["a"], [28, 15])
        XCTAssertEqual(history.utilization["a"], [20, 30])
    }

    func testRecordKeepsSeriesSeparatePerNetwork() {
        var history = NetworkHistory()
        history.record(makeNetwork(id: "a", signal: -50), maxPoints: 5)
        history.record(makeNetwork(id: "b", signal: -70), maxPoints: 5)

        XCTAssertEqual(history.signal["a"], [-50])
        XCTAssertEqual(history.signal["b"], [-70])
    }

    func testStatisticsReadFromRecordedSeries() throws {
        var history = NetworkHistory()
        history.record(makeNetwork(id: "a", signal: -50, utilization: 10), maxPoints: 5)
        history.record(makeNetwork(id: "a", signal: -70, utilization: 30), maxPoints: 5)

        let signal = try XCTUnwrap(history.signalStatistics(for: "a"))
        let utilization = try XCTUnwrap(history.utilizationStatistics(for: "a"))
        XCTAssertEqual(signal.minimum, -70)
        XCTAssertEqual(signal.maximum, -50)
        XCTAssertEqual(utilization.averageRounded, 20)
        XCTAssertNil(history.signalStatistics(for: "missing"))
    }

    func testRemoveClearsEverySeries() {
        var history = NetworkHistory()
        history.record(makeNetwork(id: "a", signal: -50, utilization: 10), maxPoints: 5)
        history.remove("a")

        XCTAssertNil(history.signal["a"])
        XCTAssertNil(history.noise["a"])
        XCTAssertNil(history.snr["a"])
        XCTAssertNil(history.utilization["a"])
    }
}
