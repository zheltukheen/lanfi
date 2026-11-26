import XCTest

@testable import LanFiCore

/// G8: capability decoding and the RSSI locator, tested without a capture,
/// CoreWLAN or a running app.
final class ClientSignalCoreTests: XCTestCase {

    // MARK: - Capability decoding

    private func element(_ id: UInt8, _ payload: [UInt8]) -> Data {
        Data([id, UInt8(payload.count)] + payload)
    }

    private var associationRequestIEs: Data {
        var ies = Data()
        // Supported rates: 1, 2, 5.5, 11, 6, 12, 24, 54 Mbit/s.
        ies += element(1, [0x82, 0x84, 0x8B, 0x96])
        ies += element(50, [0x0C, 0x18, 0x30, 0x6C])
        // HT Capabilities with a 2-stream RX MCS mask.
        var ht = [UInt8](repeating: 0, count: 26)
        ht[3] = 0xFF
        ht[4] = 0xFF  // bits 0–15 set, so two streams
        ies += element(45, ht)
        // VHT Capabilities with a 2-stream MCS map.
        var vht = [UInt8](repeating: 0, count: 12)
        vht[4] = 0xFA
        vht[5] = 0xFF  // stream 1 supports MCS 0–8
        vht[6] = 0xFA
        vht[7] = 0xFF  // stream 2 supports MCS 0–8
        vht[8] = 0xFF
        vht[9] = 0xFF  // streams 3–4 are unsupported
        vht[10] = 0xFF
        vht[11] = 0xFF
        ies += element(191, vht)
        // HE Capabilities extension.
        ies += element(255, [35, 0x00, 0x00])
        // Mobility domain (802.11r) and an RSN element with MFPC set.
        ies += element(54, [0x00, 0x01])
        ies += element(
            48,
            [
                0x01, 0x00, 0x00, 0x0F, 0xAC, 0x04, 0x01, 0x00, 0x00, 0x0F, 0xAC, 0x04,
                0x01, 0x00, 0x00, 0x0F, 0xAC, 0x02, 0x80, 0x00,
            ])
        return ies
    }

    func testAssociationRequestDecodesPHYRatesStreamsAndSecurity() throws {
        let summary = try XCTUnwrap(
            ClientCapabilitySummary.decode(
                ieBytes: associationRequestIEs, source: .associationRequest))

        XCTAssertEqual(summary.phy, [.n, .ac, .ax])
        XCTAssertEqual(summary.generation, .ax)
        XCTAssertEqual(summary.streams, 2)
        XCTAssertEqual(summary.supportedRatesMbps.first, 1)
        XCTAssertEqual(summary.supportedRatesMbps.last, 54)
        XCTAssertTrue(summary.fastTransition)
        XCTAssertTrue(summary.pmfCapable)
        XCTAssertEqual(summary.source, .associationRequest)
        XCTAssertTrue(summary.summaryLine.contains("11ax"))
        XCTAssertTrue(summary.summaryLine.contains("2×2 MIMO"))
        XCTAssertEqual(summary.ratesLabel, "1–54 Mbit/s")
    }

    func testEHTExtensionPromotesTheGeneration() throws {
        var ies = Data()
        ies += element(1, [0x8C, 0x12, 0x98, 0x24])
        ies += element(255, [107, 0x00])
        let summary = try XCTUnwrap(
            ClientCapabilitySummary.decode(ieBytes: ies, source: .beacon))
        XCTAssertEqual(summary.generation, .be)
        XCTAssertEqual(summary.source, .beacon)
    }

    func testRatesOnlyAtLegacySpeedsIsAn11bClient() throws {
        let summary = try XCTUnwrap(
            ClientCapabilitySummary.decode(
                ieBytes: element(1, [0x82, 0x84, 0x8B, 0x96]), source: .associationRequest))
        XCTAssertEqual(summary.phy, [.b])
        XCTAssertNil(summary.streams)
    }

    func testEmptyOrTruncatedBytesDoNotInventCapabilities() {
        XCTAssertNil(ClientCapabilitySummary.decode(ieBytes: Data(), source: .beacon))
        XCTAssertNil(
            ClientCapabilitySummary.decode(ieBytes: Data([45, 40]), source: .beacon),
            "a declared length larger than the data is not decoded")
    }

    // MARK: - Signal locator

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + seconds)
    }

    func testSmoothingFollowsTheSignalAndIgnoresInvalidReadings() {
        var locator = SignalLocator(smoothingFactor: 0.5)
        locator.ingest(rssi: -80, at: date(0))
        locator.ingest(rssi: -60, at: date(0.25))
        XCTAssertEqual(locator.state.smoothedRSSI ?? 0, -70, accuracy: 0.001)
        XCTAssertEqual(locator.state.sampleCount, 2)

        locator.ingest(rssi: 0, at: date(0.5))
        XCTAssertEqual(locator.state.sampleCount, 2, "0 dBm is CoreWLAN's 'unknown'")
        XCTAssertEqual(locator.state.smoothedRSSI ?? 0, -70, accuracy: 0.001)
    }

    func testTrendTurnsPositiveWhenWalkingTowardTheTransmitter() {
        var locator = SignalLocator(smoothingFactor: 0.5)
        for step in 0...4 {
            locator.ingest(rssi: -75 + step * 4, at: date(Double(step) * 0.5))
        }
        let trend = try? XCTUnwrap(locator.state.trendDBmPerSecond)
        XCTAssertEqual(trend ?? 0, 8, accuracy: 0.0001)
        XCTAssertEqual(locator.state.trendLabel, "Getting stronger")
        XCTAssertEqual(locator.state.proximity, .good)
    }

    func testSilenceAfterTheTimeoutReportsSignalLost() {
        var locator = SignalLocator(lostAfter: 3)
        locator.ingest(rssi: -50, at: date(0))
        XCTAssertEqual(locator.state.proximity, .strong)

        locator.tick(at: date(2))
        XCTAssertFalse(locator.state.isLost)
        XCTAssertEqual(locator.state.proximity, .strong)

        locator.tick(at: date(4))
        XCTAssertTrue(locator.state.isLost)
        XCTAssertNil(locator.state.smoothedRSSI)
        XCTAssertEqual(locator.state.proximity, .lost)
        XCTAssertEqual(locator.state.sampleCount, 1, "lost samples are not counted as readings")
    }

    func testNewReadingAfterLossRecoversAndResetClearsState() {
        var locator = SignalLocator(smoothingFactor: 0.5, lostAfter: 3)
        locator.ingest(rssi: -50, at: date(0))
        locator.tick(at: date(4))
        XCTAssertTrue(locator.state.isLost)

        locator.ingest(rssi: -70, at: date(5))
        XCTAssertFalse(locator.state.isLost)
        XCTAssertEqual(locator.state.proximity, .fair)
        XCTAssertEqual(locator.state.sampleCount, 2)

        locator.reset()
        XCTAssertNil(locator.state.smoothedRSSI)
        XCTAssertEqual(locator.state.sampleCount, 0)
    }

    func testProximityThresholds() {
        XCTAssertEqual(SignalProximity.forRSSI(-40), .strong)
        XCTAssertEqual(SignalProximity.forRSSI(-60), .good)
        XCTAssertEqual(SignalProximity.forRSSI(-70), .fair)
        XCTAssertEqual(SignalProximity.forRSSI(-85), .far)
    }
}
