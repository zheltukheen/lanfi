import XCTest

final class PortScannerTests: XCTestCase {

    func testScanSortsAndDeduplicatesPorts() async {
        let scanner = PortScanner(probe: TrackingPortProbe())
        let results = await scanner.scan(
            host: "example.com",
            ports: [443, 80, 22, 80, 8080, 53],
            timeout: 0.05,
            concurrency: 3
        )
        XCTAssertEqual(results.map(\.port), [22, 53, 80, 443, 8080])
        XCTAssertEqual(results.first(where: { $0.port == 80 })?.state, .open)
        XCTAssertEqual(results.first(where: { $0.port == 80 })?.service, "HTTP")
    }

    func testScanRespectsConcurrencyLimit() async {
        let probe = TrackingPortProbe()
        let scanner = PortScanner(probe: probe)
        _ = await scanner.scan(
            host: "example.com",
            ports: Array(1...12).map(UInt16.init),
            timeout: 0.05,
            concurrency: 3
        )
        let maximum = await probe.maximumConcurrent
        XCTAssertLessThanOrEqual(maximum, 3)
    }

    func testScanOfNoPortsDoesNothing() async {
        let probe = TrackingPortProbe()
        let scanner = PortScanner(probe: probe)
        let results = await scanner.scan(host: "example.com", ports: [])
        XCTAssertTrue(results.isEmpty)
        let calls = await probe.calls
        XCTAssertEqual(calls, 0)
    }
}

private actor TrackingPortProbe: PortProbing {
    private var active = 0
    private(set) var maximumConcurrent = 0
    private(set) var calls = 0

    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortScanResult {
        calls += 1
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        try? await Task.sleep(nanoseconds: 2_000_000)
        active -= 1
        return PortScanResult(
            port: port,
            service: PortServices.name(for: port),
            state: port == 80 ? .open : .closed
        )
    }
}
