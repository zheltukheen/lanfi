import XCTest

final class ProcessTrafficTests: XCTestCase {
    private let fixture = """
        \u{20}                                   bytes_in       bytes_out
        kernel_task.0                              1000           2000
        Google Chrome Helper.4321                  500            250
        com.apple.WebKit.Networking.9876             0              0
        malformed line
        """

    func testParsesProcessNamesWithSpacesAndDots() {
        let rows = ProcessTrafficParser.parse(fixture)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first?.process, "kernel_task")
        XCTAssertEqual(rows.first?.pid, 0)
        XCTAssertEqual(rows.first?.bytesIn, 1000)
        XCTAssertEqual(rows.first?.bytesOut, 2000)
        XCTAssertTrue(rows.contains { $0.process == "Google Chrome Helper" && $0.pid == 4321 })
        XCTAssertTrue(rows.contains { $0.process == "com.apple.WebKit.Networking" })
    }

    func testDeltasClampCounterResetsAndComputeRates() throws {
        let previous = [
            ProcessTrafficRow(process: "Safari", pid: 10, bytesIn: 100, bytesOut: 50),
            ProcessTrafficRow(process: "Mail", pid: 20, bytesIn: 500, bytesOut: 500),
        ]
        let current = [
            ProcessTrafficRow(process: "Safari", pid: 10, bytesIn: 300, bytesOut: 150),
            ProcessTrafficRow(process: "Mail", pid: 20, bytesIn: 10, bytesOut: 600),
            ProcessTrafficRow(process: "New", pid: 30, bytesIn: 40, bytesOut: 20),
        ]

        let deltas = ProcessTrafficParser.deltas(
            previous: previous, current: current, interval: 2)
        let safari = try XCTUnwrap(deltas.first { $0.process == "Safari" })
        XCTAssertEqual(safari.receivedBytes, 200)
        XCTAssertEqual(safari.sentBytes, 100)
        XCTAssertEqual(safari.receivedBytesPerSecond, 100, accuracy: 0.001)
        XCTAssertEqual(safari.sentBytesPerSecond, 50, accuracy: 0.001)

        let mail = try XCTUnwrap(deltas.first { $0.process == "Mail" })
        XCTAssertEqual(mail.receivedBytes, 0, "a restarted counter must not go negative")
        XCTAssertEqual(mail.sentBytes, 100)

        XCTAssertEqual(deltas.first?.process, "Safari")
    }

    func testFormatting() {
        XCTAssertEqual(ProcessTrafficFormat.rate(0), "0 B/s")
        XCTAssertEqual(ProcessTrafficFormat.rate(1500), "1.5 KB/s")
        XCTAssertFalse(ProcessTrafficFormat.bytes(2_000).isEmpty)
    }
}
