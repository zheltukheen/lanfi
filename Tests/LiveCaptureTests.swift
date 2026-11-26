import XCTest

final class LiveCaptureTests: XCTestCase {
    func testMonitorModeCommandContainsRadiotapAndDuration() throws {
        let url = URL(fileURLWithPath: "/tmp/LanFi test.pcap")
        let options = LiveCaptureOptions(
            interfaceName: "en0", duration: 15, outputURL: url, monitorMode: true,
            filter: "type mgt",
            startDelay: 5
        )
        try LiveCaptureService.validate(options)
        let command = LiveCaptureService.shellCommand(for: options)
        XCTAssertTrue(command.contains("/usr/sbin/tcpdump"))
        XCTAssertTrue(command.contains("-I -y IEEE802_11_RADIO"))
        XCTAssertTrue(command.contains("/tmp/LanFi test.pcap"))
        XCTAssertTrue(command.contains("$i -lt 15"))
        XCTAssertTrue(command.contains("kill -TERM $PID"))
        XCTAssertTrue(command.contains("type mgt"))
        XCTAssertTrue(command.contains("sleep 5"))
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
            interfaceName: "en0", duration: 900,
            outputURL: URL(fileURLWithPath: "/tmp/x.pcap"), monitorMode: false
        )
        XCTAssertThrowsError(try LiveCaptureService.validate(options))
    }

    func testSizeCapAddsRotationAndStopFileCheck() {
        let url = URL(fileURLWithPath: "/tmp/rotating.pcap")
        let options = LiveCaptureOptions(
            interfaceName: "en0", duration: 300, outputURL: url, monitorMode: true,
            limits: CaptureLimits(maxFileSizeMB: 50, sliceDataFrameBytes: nil))
        let command = LiveCaptureService.shellCommand(for: options)
        XCTAssertTrue(command.contains("-C 50"), command)
        XCTAssertTrue(command.contains("/tmp/rotating.pcap.stop"), command)
        XCTAssertTrue(command.contains("$i -lt 300"), command)
        // The rotation applies to the named file and its numbered siblings.
        XCTAssertTrue(command.contains("'/tmp/rotating.pcap'*"), command)
    }

    func testStreamingSkipsRotationBecauseWiresharkTailsOneFile() {
        let options = LiveCaptureOptions(
            interfaceName: "en0", duration: 30,
            outputURL: URL(fileURLWithPath: "/tmp/stream.pcap"), monitorMode: true,
            limits: CaptureLimits(maxFileSizeMB: 50, sliceDataFrameBytes: nil),
            streamToWireshark: true)
        let command = LiveCaptureService.shellCommand(for: options)
        XCTAssertFalse(command.contains("-C 50"), command)
    }

    func testStopFileSitsNextToTheCapture() {
        let url = URL(fileURLWithPath: "/tmp/stop.pcap")
        XCTAssertEqual(LiveCaptureService.stopURL(for: url).path, "/tmp/stop.pcap.stop")
    }
}
