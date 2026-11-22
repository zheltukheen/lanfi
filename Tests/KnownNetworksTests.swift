import XCTest

final class KnownNetworksInsightsTests: XCTestCase {
    private let saved = [
        KnownNetwork(ssid: "Home"),
        KnownNetwork(ssid: "Cafe"),
        KnownNetwork(ssid: "Office"),
    ]

    private func visible() -> [NetworkModel] {
        [
            makeNetwork(
                bssid: "AA:00:00:00:00:01", ssid: "Home", band: .band5, channel: 36, security: "WPA3 Personal",
                signal: -55),
            makeNetwork(
                bssid: "AA:00:00:00:00:02", ssid: "Home", band: .band24, channel: 6, security: "WPA3 Personal",
                signal: -70),
            makeNetwork(bssid: "BB:00:00:00:00:01", ssid: "Cafe", security: "Open", signal: -60),
            makeNetwork(bssid: "CC:00:00:00:00:01", ssid: "Neighbour", security: "WPA2 Personal", signal: -80),
        ]
    }

    func testRowsGroupAccessPointsAndKeepSavedOrder() {
        let rows = KnownNetworksAnalysis.rows(saved: saved, visible: visible())
        XCTAssertEqual(rows.map(\.ssid), ["Home", "Cafe", "Office"])
        XCTAssertEqual(rows[0].accessPoints.count, 2)
        XCTAssertEqual(rows[0].best?.signal, -55)
        XCTAssertEqual(rows[0].bssidCount, 2)
        XCTAssertEqual(rows[0].channels, [6, 36])
        XCTAssertFalse(rows[2].isInRange)
    }

    func testFilterAndSort() {
        let rows = KnownNetworksAnalysis.rows(saved: saved, visible: visible())
        let inRange = KnownNetworksAnalysis.filtered(rows, filter: .inRange, sort: .signal)
        XCTAssertEqual(inRange.map(\.ssid), ["Home", "Cafe"])
        let out = KnownNetworksAnalysis.filtered(rows, filter: .outOfRange, sort: .name)
        XCTAssertEqual(out.map(\.ssid), ["Office"])
        let insecure = KnownNetworksAnalysis.filtered(rows, filter: .insecure, sort: .name)
        XCTAssertEqual(insecure.map(\.ssid), ["Cafe"])
    }

    func testSummaryAndUnsavedVisible() {
        let rows = KnownNetworksAnalysis.rows(saved: saved, visible: visible())
        let summary = KnownNetworksAnalysis.summary(rows: rows, visible: visible())
        XCTAssertEqual(summary.saved, 3)
        XCTAssertEqual(summary.inRange, 2)
        XCTAssertEqual(summary.outOfRange, 1)
        XCTAssertEqual(summary.insecure, 1)
        XCTAssertEqual(summary.unsavedVisible, 1)
        XCTAssertEqual(
            KnownNetworksAnalysis.unsavedVisible(saved: saved, visible: visible()).map(\.ssid),
            ["Neighbour"])
    }

    func testWeakSecurityClassification() {
        XCTAssertTrue(KnownNetworkSecurity(label: "Open").isInsecure)
        XCTAssertTrue(KnownNetworkSecurity(label: "WEP").isInsecure)
        XCTAssertTrue(KnownNetworkSecurity(label: "WPA Personal").isInsecure)
        XCTAssertFalse(KnownNetworkSecurity(label: "WPA2 Personal").isInsecure)
        XCTAssertFalse(KnownNetworkSecurity(label: "WPA3 Personal").isInsecure)
        XCTAssertTrue(KnownNetworkSecurity(label: "OWE Transition").isWPA3)
        XCTAssertFalse(KnownNetworkSecurity(label: "").isInsecure)
    }

    func testCSVEscapesTheSSIDAndUsesBestBSSID() {
        let rows = KnownNetworksAnalysis.rows(
            saved: [KnownNetwork(ssid: "Guest, 5G")], visible: visible())
        let csv = KnownNetworksAnalysis.csv(rows: rows)
        XCTAssertTrue(csv.hasPrefix("ssid,bssid,signal_dbm"))
        XCTAssertTrue(csv.contains("\"Guest, 5G\""))
        XCTAssertTrue(csv.contains(",,,"))
    }

    func testJSONContainsAccessPointCount() throws {
        let rows = KnownNetworksAnalysis.rows(saved: saved, visible: visible())
        let data = KnownNetworksAnalysis.json(rows: rows)
        let objects = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(objects.count, 3)
        XCTAssertEqual(objects.first?["accessPointCount"] as? Int, 2)
    }
}
