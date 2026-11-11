import XCTest

final class Iperf3HistoryTests: XCTestCase {

    func testRoundTripMeasurements() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iperf3-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = Iperf3HistoryStore(fileURL: url)
        let measurement = Iperf3Measurement(
            host: "192.168.1.10", port: 5201, direction: .download,
            headlineMegabitsPerSecond: 812.5, testedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save([measurement])
        let loaded = try store.load()
        XCTAssertEqual(loaded, [measurement])
    }
}
