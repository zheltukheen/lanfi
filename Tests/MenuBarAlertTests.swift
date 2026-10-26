import XCTest

final class MenuBarAlertTests: XCTestCase {
    func testWeakConnectedNetworkRaisesCriticalAlert() {
        let network = makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", ssid: "Weak", signal: -82)
        let alerts = MenuBarAlertEngine.compute(
            networks: [network], connectedBSSID: network.bssid,
            weakSignalEnabled: true, openNetworkEnabled: false, channelChangeEnabled: false,
            previousChannel: nil
        )
        XCTAssertEqual(alerts.first?.id, "weak-signal")
        XCTAssertEqual(alerts.first?.severity, .critical)
    }

    func testOpenNetworksAreAggregated() {
        let open = makeNetwork(bssid: "AA:BB:CC:DD:EE:01", ssid: "Open", security: "Open", signal: -50)
        let secure = makeNetwork(bssid: "AA:BB:CC:DD:EE:02", ssid: "Secure", security: "WPA2", signal: -50)
        let alerts = MenuBarAlertEngine.compute(
            networks: [open, secure], connectedBSSID: nil,
            weakSignalEnabled: false, openNetworkEnabled: true, channelChangeEnabled: false,
            previousChannel: nil
        )
        XCTAssertEqual(alerts.first?.id, "open-network")
        XCTAssertTrue(alerts.first?.title.contains("1 open network") == true)
    }

    func testChannelChangeAlert() {
        let network = makeNetwork(bssid: "AA:BB:CC:DD:EE:FF", ssid: "Roam", channel: 44, signal: -50)
        let alerts = MenuBarAlertEngine.compute(
            networks: [network], connectedBSSID: network.bssid,
            weakSignalEnabled: false, openNetworkEnabled: false, channelChangeEnabled: true,
            previousChannel: 36
        )
        XCTAssertEqual(alerts.first?.id, "channel-change")
    }
}
