import XCTest

final class ScanHealthTests: XCTestCase {
    private func network(ssid: String, bssid: String) -> NetworkModel {
        NetworkModel(
            summaryID: bssid.isEmpty ? "hidden" : bssid,
            bssid: bssid, ssid: ssid, band: .band5, channel: 36,
            generation: .mode11ax, security: "WPA2", signal: -55)
    }

    func testHealthyWhenIdentifiersVisible() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [network(ssid: "Home", bssid: "AA:BB:CC:DD:EE:01")],
            errorMessage: nil, isLocationAuthorized: true)
        XCTAssertEqual(health, .healthy)
        XCTAssertFalse(health.requiresBanner)
    }

    func testEmptyIdentifiersAreReportedAsHiddenNotAsHiddenSSID() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [network(ssid: "", bssid: ""), network(ssid: "", bssid: "")],
            errorMessage: nil, isLocationAuthorized: true)
        XCTAssertEqual(health, .identifiersHidden)
        XCTAssertTrue(health.requiresBanner)
    }

    func testHiddenSSIDWithVisibleBSSIDIsHealthy() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [network(ssid: "", bssid: "AA:BB:CC:DD:EE:02")],
            errorMessage: nil, isLocationAuthorized: true)
        XCTAssertEqual(health, .healthy)
    }

    func testEmptyScanWithoutPermissionIsPermissionDenied() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [], errorMessage: nil, isLocationAuthorized: false)
        XCTAssertEqual(health, .permissionDenied)
        XCTAssertFalse(health.requiresBanner)
    }

    func testEmptyScanWithPermissionIsNoNetworks() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [], errorMessage: nil, isLocationAuthorized: true)
        XCTAssertEqual(health, .noNetworks)
    }

    func testErrorWinsOverRows() {
        let health = ScanHealthEvaluator.evaluate(
            networks: [network(ssid: "Home", bssid: "AA:BB:CC:DD:EE:03")],
            errorMessage: "Wi-Fi is off", isLocationAuthorized: true)
        XCTAssertEqual(health, .scanFailed("Wi-Fi is off"))
    }
}
