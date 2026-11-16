import XCTest

final class ScanMetricsTests: XCTestCase {
    private func network(
        band: WiFiBand = .band6,
        channel: Int = 37,
        beaconAirtime: Double? = nil
    ) -> NetworkModel {
        NetworkModel(
            id: "id", bssid: "AA:BB:CC:DD:EE:FF", ssid: "Home", band: band,
            channel: channel, channelWidthMHz: 80, generation: .mode11be,
            security: "WPA3", vendor: "Netgear", apName: nil,
            mode: "Infrastructure", signal: -60, noise: -92, snr: 32,
            basicRates: nil, minBasicRate: nil, maxBasicRate: nil, minRate: nil,
            maxRate: 1200, centerFrequency: nil, channelUtilization: 20,
            beaconInterval: 100, beaconRate: 6, beaconAirtime: beaconAirtime,
            beaconMode: nil, countryCode: nil, fastTransition: nil,
            protectionMode: nil, stations: nil, clients: nil, streams: 2,
            type: nil, wps: nil, wpsEnabled: nil, pmfRequired: nil, ieCount: 0,
            ieTotalLength: nil, ratesEstimated: false, informationElements: [],
            count: 1, firstSeen: Date(), lastSeen: Date())
    }

    func testSSIDOverheadConvertsMillisecondsPerSecondToPercent() {
        XCTAssertEqual(network(beaconAirtime: 25).ssidOverheadPercent ?? -1, 2.5, accuracy: 0.001)
    }

    func testSSIDOverheadIsNilWithoutBeaconAirtime() {
        XCTAssertNil(network(beaconAirtime: nil).ssidOverheadPercent)
    }

    func testSSIDOverheadIsClampedToFullChannel() {
        XCTAssertEqual(network(beaconAirtime: 4000).ssidOverheadPercent, 100)
    }

    func testPSCMembershipOnSixGHzOnly() {
        XCTAssertTrue(network(channel: 37).isPreferredScanningChannel)
        XCTAssertTrue(network(channel: 5).isPreferredScanningChannel)
        XCTAssertFalse(network(channel: 33).isPreferredScanningChannel)
        XCTAssertFalse(network(band: .band5, channel: 37).isPreferredScanningChannel)
    }

    func testAnalyzerPSCMatchesModel() {
        XCTAssertTrue(NetworkAnalyzer.isPreferredScanningChannel(band: .band6, channel: 69))
        XCTAssertFalse(NetworkAnalyzer.isPreferredScanningChannel(band: .band6, channel: 71))
    }

    func testColumnFormatsOverhead() {
        let formatter = NetworkColumnFormatter(
            signalDisplayMode: .dbm, connectedBSSID: nil, metricsByNetworkId: [:])
        XCTAssertEqual(formatter.text(for: .ssidOverhead, network: network(beaconAirtime: 34)), "3.4%")
        XCTAssertEqual(formatter.text(for: .ssidOverhead, network: network()), "-")
    }
}
