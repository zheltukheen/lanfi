import XCTest

final class TracerouteRunnerTests: XCTestCase {
    func testArgumentsAreBounded() {
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(host: "example.com", maxHops: 30, waitSeconds: 2),
            ["-n", "-m", "30", "-w", "2", "-q", "1", "example.com"])
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(host: "example.com", maxHops: 0, waitSeconds: 0),
            ["-n", "-m", "1", "-w", "1", "-q", "1", "example.com"])
    }
}
