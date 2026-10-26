import XCTest

final class LiveCaptureTests: XCTestCase {
    func testMonitorModeCommandContainsRadiotapAndDuration() throws {
        let url = URL(fileURLWithPath: "/tmp/LanFi test.pcap")
        let options = LiveCaptureOptions(
            interfaceName: "en0", duration: 15, outputURL: url, monitorMode: true
        )
        try LiveCaptureService.validate(options)
        let command = LiveCaptureService.shellCommand(for: options)
        XCTAssertTrue(command.contains("/usr/sbin/tcpdump"))
        XCTAssertTrue(command.contains("-I -y IEEE802_11_RADIO"))
        XCTAssertTrue(command.contains("/tmp/LanFi test.pcap"))
        XCTAssertTrue(command.contains("sleep 15"))
        XCTAssertFalse(command.contains("\n"))
        XCTAssertFalse(command.contains("&;"))
    }

    func testEthernetCommandOmitsMonitorFlags() {
        let options = LiveCaptureOptions(
            interfaceName: "en5", duration: 10,
            outputURL: URL(fileURLWithPath: "/tmp/ethernet.pcap"), monitorMode: false
        )
        let command = LiveCaptureService.shellCommand(for: options)
        XCTAssertFalse(command.contains("IEEE802_11_RADIO"))
        XCTAssertTrue(command.contains("chown"))
    }

    func testRejectsUnsafeInterfaceName() {
        let options = LiveCaptureOptions(
            interfaceName: "en0; rm -rf /", duration: 10,
            outputURL: URL(fileURLWithPath: "/tmp/x.pcap"), monitorMode: false
        )
        XCTAssertThrowsError(try LiveCaptureService.validate(options))
    }

    func testRejectsOutOfRangeDuration() {
        let options = LiveCaptureOptions(
            interfaceName: "en0", duration: 500,
            outputURL: URL(fileURLWithPath: "/tmp/x.pcap"), monitorMode: false
        )
        XCTAssertThrowsError(try LiveCaptureService.validate(options))
    }
}
