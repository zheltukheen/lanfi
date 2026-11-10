import XCTest

final class PingServiceTests: XCTestCase {

    func testRunCollectsSamplesFromProbe() async {
        let probe = FakePingProbe(rtts: [10, nil, 30])
        let service = PingService(probe: probe)
        let stats = await service.run(host: "example.com", count: 3, interval: 0, timeout: 0.1)

        XCTAssertEqual(stats.host, "example.com")
        XCTAssertEqual(stats.transmitted, 3)
        XCTAssertEqual(stats.received, 2)
        XCTAssertEqual(stats.packetLossPercent, 100.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(stats.minMilliseconds, 10)
        XCTAssertEqual(stats.maxMilliseconds, 30)
        XCTAssertEqual(stats.averageMilliseconds, 20)
    }

    func testRunAlwaysSendsAtLeastOneProbe() async {
        let probe = FakePingProbe(rtts: [12])
        let service = PingService(probe: probe)
        let stats = await service.run(host: "example.com", count: 0, interval: 0)
        XCTAssertEqual(stats.transmitted, 1)
    }

    func testRunCapsVeryLargeCounts() async {
        let probe = CountingPingProbe()
        let service = PingService(probe: probe)
        _ = await service.run(host: "example.com", count: 20_000, interval: 0)
        let calls = await probe.calls
        XCTAssertEqual(calls, 10_000)
    }
}

private struct FakePingProbe: PingProbing {
    let rtts: [Double?]

    func probe(host: String, sequence: Int, timeout: TimeInterval) async -> PingSample {
        let rtt = sequence - 1 < rtts.count ? rtts[sequence - 1] : nil
        return PingSample(
            sequence: sequence, rttMilliseconds: rtt, error: rtt == nil ? "Timed out" : nil)
    }
}

private actor CountingPingProbe: PingProbing {
    private(set) var calls = 0

    func probe(host: String, sequence: Int, timeout: TimeInterval) async -> PingSample {
        calls += 1
        return PingSample(sequence: sequence, rttMilliseconds: 1)
    }
}
