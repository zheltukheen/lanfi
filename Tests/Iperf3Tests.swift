import XCTest

final class Iperf3Tests: XCTestCase {

    func testParsesJSONReport() throws {
        let json = """
            {
              "intervals": [
                {"sum": {"start": 0, "end": 1, "bits_per_second": 100000000}},
                {"sum": {"start": 1, "end": 2, "bits_per_second": 120000000}}
              ],
              "end": {
                "sum_sent": {"bits_per_second": 110000000},
                "sum_received": {"bits_per_second": 115000000},
                "sum": {"bits_per_second": 112500000}
              }
            }
            """
        let report = try Iperf3Parser.parse(
            Data(json.utf8), host: "example.com", port: 5201, direction: .upload)

        XCTAssertEqual(report.host, "example.com")
        XCTAssertEqual(report.port, 5201)
        XCTAssertEqual(report.sentMegabitsPerSecond ?? 0, 110, accuracy: 0.001)
        XCTAssertEqual(report.receivedMegabitsPerSecond ?? 0, 115, accuracy: 0.001)
        XCTAssertEqual(report.headlineMegabitsPerSecond ?? 0, 110, accuracy: 0.001)
        XCTAssertEqual(report.intervals.count, 2)
        XCTAssertEqual(report.intervals[1].megabitsPerSecond, 120, accuracy: 0.001)
        XCTAssertEqual(report.durationSeconds ?? 0, 2, accuracy: 0.001)
    }

    func testHeadlineFollowsDirection() throws {
        let json = """
            {"intervals": [], "end": {"sum_sent": {"bits_per_second": 10000000},
             "sum_received": {"bits_per_second": 20000000},
             "sum": {"bits_per_second": 30000000}}}
            """
        let download = try Iperf3Parser.parse(
            Data(json.utf8), host: "h", port: 1, direction: .download)
        XCTAssertEqual(download.headlineMegabitsPerSecond ?? 0, 20, accuracy: 0.001)

        let bidirectional = try Iperf3Parser.parse(
            Data(json.utf8), host: "h", port: 1, direction: .bidirectional)
        XCTAssertEqual(bidirectional.headlineMegabitsPerSecond ?? 0, 30, accuracy: 0.001)
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(
            try Iperf3Parser.parse(Data("not json".utf8), host: "h", port: 1, direction: .upload)
        ) { error in
            XCTAssertEqual(error as? Iperf3Error, .invalidOutput)
        }
    }

    func testArgumentsCoverDirections() {
        XCTAssertEqual(
            Iperf3Runner.arguments(
                host: "example.com", port: 5201, durationSeconds: 10, direction: .upload),
            ["-c", "example.com", "-p", "5201", "-t", "10", "-J"])
        XCTAssertTrue(
            Iperf3Runner.arguments(
                host: "example.com", port: 5201, durationSeconds: 10, direction: .download
            ).contains("-R"))
        XCTAssertTrue(
            Iperf3Runner.arguments(
                host: "example.com", port: 5201, durationSeconds: 10, direction: .bidirectional
            ).contains("--bidir"))
    }
}
