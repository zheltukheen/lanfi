import XCTest

final class RoamProbeTests: XCTestCase {
    private func transition(at: Date) -> RoamTransition {
        RoamTransition(
            id: "roam-1", at: at, fromBSSID: "AA:AA:AA:AA:AA:AA",
            toBSSID: "BB:BB:BB:BB:BB:BB", rssiBefore: -62, rssiAfter: -58)
    }

    private func probe(_ offset: TimeInterval, reached: Bool, at: Date) -> RoamProbeSample {
        RoamProbeSample(
            at: at.addingTimeInterval(offset), reached: reached,
            latencyMilliseconds: reached ? 4 : nil)
    }

    func testImpactMeasuresLossAndReconnect() throws {
        let at = Date(timeIntervalSince1970: 1_000)
        let probes = [
            probe(-2, reached: true, at: at),
            probe(-1, reached: true, at: at),
            probe(0.2, reached: false, at: at),
            probe(1.2, reached: false, at: at),
            probe(2.2, reached: true, at: at),
        ]
        let impact = try XCTUnwrap(
            RoamProbeAnalyzer.impact(for: transition(at: at), probes: probes))
        XCTAssertEqual(impact.probes, 5)
        XCTAssertEqual(impact.packetLossPercent, 40, accuracy: 0.01)
        XCTAssertEqual(impact.reconnectMilliseconds, 3_200)
    }

    func testCleanRoamHasNoLoss() throws {
        let at = Date(timeIntervalSince1970: 2_000)
        let probes = [
            probe(-1, reached: true, at: at), probe(1, reached: true, at: at),
        ]
        let impact = try XCTUnwrap(
            RoamProbeAnalyzer.impact(for: transition(at: at), probes: probes))
        XCTAssertEqual(impact.packetLossPercent, 0)
        XCTAssertEqual(impact.reconnectMilliseconds, 2_000)
    }

    func testTooFewProbesOrMissingRecoveryProduceNoOrPartialImpact() throws {
        let at = Date(timeIntervalSince1970: 3_000)
        XCTAssertNil(
            RoamProbeAnalyzer.impact(
                for: transition(at: at), probes: [probe(0, reached: true, at: at)]))

        let downAfter = [probe(-1, reached: true, at: at), probe(1, reached: false, at: at)]
        let impact = try XCTUnwrap(
            RoamProbeAnalyzer.impact(for: transition(at: at), probes: downAfter))
        XCTAssertNil(impact.reconnectMilliseconds)
        XCTAssertEqual(impact.packetLossPercent, 50, accuracy: 0.01)
    }

    func testProbesOutsideTheWindowAreIgnored() throws {
        let at = Date(timeIntervalSince1970: 4_000)
        let probes = [
            probe(-20, reached: false, at: at), probe(20, reached: false, at: at),
            probe(0, reached: true, at: at), probe(1, reached: true, at: at),
        ]
        let impact = try XCTUnwrap(
            RoamProbeAnalyzer.impact(for: transition(at: at), probes: probes))
        XCTAssertEqual(impact.probes, 2)
        XCTAssertEqual(impact.packetLossPercent, 0)
    }
}
