import XCTest

final class ClientAnalyticsTests: XCTestCase {
    private func network(
        _ bssid: String, ssid: String = "Office", clients: Int? = nil, utilization: Int? = nil
    ) -> NetworkModel {
        NetworkModel(
            id: bssid, bssid: bssid, ssid: ssid, band: .band5, channel: 36,
            channelWidthMHz: 80, generation: .mode11ax, security: "WPA3", vendor: "-",
            apName: nil, mode: "Infrastructure", signal: -55, noise: nil, snr: nil,
            basicRates: nil, minBasicRate: nil, maxBasicRate: nil, minRate: nil,
            maxRate: nil, centerFrequency: nil, channelUtilization: utilization,
            beaconInterval: nil, beaconRate: nil, beaconAirtime: nil, beaconMode: nil,
            countryCode: nil, fastTransition: nil, protectionMode: nil, stations: nil,
            clients: clients, streams: nil, type: nil, wps: nil, wpsEnabled: nil,
            pmfRequired: nil, ieCount: nil, ieTotalLength: nil, ratesEstimated: false,
            informationElements: [], count: 1, firstSeen: nil, lastSeen: nil)
    }

    func testAdvertisedClientsRankAccessPoints() {
        let snapshot = ClientAnalyticsSnapshot.build(networks: [
            network("A", ssid: "Busy", clients: 12, utilization: 70),
            network("B", ssid: "Quiet", clients: 2),
            network("C", ssid: "Silent"),
        ])
        XCTAssertEqual(snapshot.advertisedClients, 14)
        XCTAssertEqual(snapshot.busiestAccessPoints.map(\.ssid), ["Busy", "Quiet"])
        XCTAssertEqual(snapshot.busiestAccessPoints.first?.clients, 12)
        XCTAssertEqual(snapshot.idleAccessPoints, 1)
        XCTAssertEqual(snapshot.accessPointCount, 3)
        XCTAssertTrue(snapshot.insights.contains { $0.contains("Busy") })
        XCTAssertTrue(snapshot.insights.contains { $0.contains("utilization") })
    }

    func testCapturedClientsAggregateUniqueMACsVendorsAndProbes() {
        let observations = [
            ClientObservation(
                mac: "aa:bb:cc:00:00:01", bssid: "A", vendor: "Acme", rssi: -60, frames: 5,
                probes: ["Office", "Guest"]),
            ClientObservation(
                mac: "aa:bb:cc:00:00:02", bssid: "A", vendor: "Acme", rssi: -80, frames: 3,
                probes: ["Office"]),
            ClientObservation(
                mac: "aa:bb:cc:00:00:01", bssid: "B", vendor: "Acme", rssi: -70, frames: 2,
                probes: ["Guest"]),
        ]
        let snapshot = ClientAnalyticsSnapshot.build(networks: [], observations: observations)
        XCTAssertEqual(snapshot.capturedClients, 2)
        XCTAssertEqual(snapshot.capturedFrames, 10)
        XCTAssertEqual(snapshot.averageCapturedRSSI, -70)
        XCTAssertEqual(snapshot.vendorMix.first, .init(value: "Acme", count: 3))
        XCTAssertEqual(snapshot.probeSSIDs.first(where: { $0.value == "Office" })?.count, 2)
        XCTAssertEqual(snapshot.probeSSIDs.first(where: { $0.value == "Guest" })?.count, 2)
    }

    func testEmptyInputExplainsMissingData() {
        let snapshot = ClientAnalyticsSnapshot.build(networks: [])
        XCTAssertEqual(snapshot.advertisedClients, 0)
        XCTAssertFalse(snapshot.insights.isEmpty)
    }
}
