import XCTest

/// P1.3 — the capture accounting that turns per-client airtime and retries into
/// the Client Analytics cards.
final class ClientAirtimeAnalyticsTests: XCTestCase {
    private func observation(
        _ mac: String, bssid: String = "AA:AA:AA:AA:AA:AA", frames: Int,
        retries: Int = 0, airtime: Int = 0, vendor: String = "Acme"
    ) -> ClientObservation {
        ClientObservation(
            mac: mac, bssid: bssid, vendor: vendor, rssi: -60, frames: frames,
            retries: retries, airtimeMicroseconds: airtime)
    }

    func testAirtimeIsSummedPerClientAcrossBSSIDs() throws {
        let snapshot = ClientAnalyticsSnapshot.build(
            networks: [],
            observations: [
                observation("AA:00:00:00:00:01", bssid: "A", frames: 10, airtime: 2_000),
                observation("AA:00:00:00:00:01", bssid: "B", frames: 10, airtime: 2_000),
                observation("AA:00:00:00:00:02", bssid: "A", frames: 5, airtime: 5_000),
            ])

        XCTAssertEqual(snapshot.totalAirtimeMicroseconds, 9_000)
        XCTAssertEqual(snapshot.clientLoads.count, 2, "one row per radio, not per association")
        let busiest = try XCTUnwrap(snapshot.clientLoads.first)
        XCTAssertEqual(busiest.mac, "AA:00:00:00:00:02")
        XCTAssertEqual(busiest.airtimeMilliseconds, 5)
        XCTAssertEqual(try XCTUnwrap(busiest.airtimeShare), 5.0 / 9.0, accuracy: 0.0001)
    }

    func testHighRetryRateProducesAnInsight() throws {
        let snapshot = ClientAnalyticsSnapshot.build(
            networks: [],
            observations: [
                observation("AA:00:00:00:00:01", frames: 20, retries: 5, airtime: 1_000),
                observation("AA:00:00:00:00:02", frames: 20, retries: 0, airtime: 1_000),
                observation("AA:00:00:00:00:03", frames: 20, retries: 0, airtime: 1_000),
            ])

        let load = snapshot.clientLoads.first { $0.mac == "AA:00:00:00:00:01" }
        XCTAssertEqual(try XCTUnwrap(load?.retryRate), 0.25, accuracy: 0.0001)
        XCTAssertTrue(snapshot.insights.contains { $0.contains("25%") && $0.contains("retries") })
    }

    func testAirtimeHogProducesAnInsightOnlyWithEnoughClients() {
        let hog = observation("AA:00:00:00:00:01", frames: 10, airtime: 6_000)
        let quiet = [
            observation("AA:00:00:00:00:02", frames: 10, airtime: 2_000),
            observation("AA:00:00:00:00:03", frames: 10, airtime: 2_000),
        ]
        let withEnough = ClientAnalyticsSnapshot.build(networks: [], observations: [hog] + quiet)
        XCTAssertTrue(withEnough.insights.contains { $0.contains("captured airtime") })

        let single = ClientAnalyticsSnapshot.build(networks: [], observations: [hog])
        XCTAssertFalse(
            single.insights.contains { $0.contains("captured airtime") },
            "a single client is the whole capture, not a hog")
    }

    func testMissingAirtimeLeavesShareEmpty() {
        let snapshot = ClientAnalyticsSnapshot.build(
            networks: [],
            observations: [observation("AA:00:00:00:00:01", frames: 5)])
        XCTAssertEqual(snapshot.totalAirtimeMicroseconds, 0)
        XCTAssertNil(snapshot.clientLoads.first?.airtimeShare)
    }
}
