import XCTest

final class RemoteCaptureTests: XCTestCase {
    func testScriptIncludesDelayFilterAndCleanup() {
        let sensor = RemoteSensor.new(name: "Sensor", host: "192.0.2.10", username: "lanfi")
        let request = RemoteCaptureRequest(
            sensor: sensor, interfaceName: "en0", duration: 20,
            monitorMode: true, filter: "type mgt"
        )
        let script = RemoteCaptureService.script(for: request, remotePath: "/tmp/test.pcap")
        XCTAssertTrue(script.contains("tcpdump"))
        XCTAssertTrue(script.contains("sleep 20"))
        XCTAssertTrue(script.contains("type mgt"))
        XCTAssertTrue(script.contains("chmod 644"))
    }

    func testRejectsUnsafeInterface() {
        let sensor = RemoteSensor.new(name: "Sensor", host: "192.0.2.10", username: "lanfi")
        let request = RemoteCaptureRequest(sensor: sensor, interfaceName: "en0; rm -rf /")
        XCTAssertThrowsError(try RemoteCaptureService.validate(request))
    }
}
