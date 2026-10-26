import XCTest

final class ThroughputTests: XCTestCase {
    func testParsesNetworkQualityJSON() {
        let report = ThroughputTester.parse([
            "dl_throughput": 523_400_000,
            "ul_throughput": 101_200_000,
            "idle_latency": 12.4,
            "responsiveness": 780,
        ])
        XCTAssertEqual(report.downloadMbps ?? 0, 523.4, accuracy: 0.1)
        XCTAssertEqual(report.uploadMbps ?? 0, 101.2, accuracy: 0.1)
        XCTAssertEqual(report.latencyMilliseconds ?? 0, 12.4, accuracy: 0.1)
        XCTAssertTrue(report.summary.contains("523 Mbps"))
    }
}
