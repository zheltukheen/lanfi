import XCTest

final class TracerouteRunnerTests: XCTestCase {
    func testArgumentsAreBounded() {
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(host: "example.com", maxHops: 30, waitSeconds: 2),
            ["-n", "-P", "icmp", "-m", "30", "-w", "2", "-q", "1", "example.com"])
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(host: "example.com", maxHops: 0, waitSeconds: 0),
            ["-n", "-P", "icmp", "-m", "1", "-w", "1", "-q", "1", "example.com"])
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(
                host: "example.com", maxHops: 30, waitSeconds: 2, probes: 3,
                resolveNames: true),
            ["-P", "icmp", "-m", "30", "-w", "2", "-q", "3", "example.com"])
    }

    func testUDPProbesAreRequestedAsFallback() {
        XCTAssertEqual(
            SystemTracerouteRunner.arguments(
                host: "1.1.1.1", maxHops: 8, waitSeconds: 1, probe: .udp),
            ["-n", "-P", "udp", "-m", "8", "-w", "1", "-q", "1", "1.1.1.1"])
    }
}
