import XCTest

final class SecurityWatchTests: XCTestCase {
    private func network(
        ssid: String = "Corp",
        bssid: String = "AA:BB:CC:DD:EE:01",
        security: String = "WPA2 Personal",
        signal: Int = -55,
        band: WiFiBand = .band5,
        vendor: String = "Test Vendor"
    ) -> NetworkModel {
        makeNetwork(
            bssid: bssid, ssid: ssid, band: band, channel: 44, security: security,
            vendor: vendor, signal: signal)
    }

    func testOpenCopyOfSecuredSSIDIsCriticalEvilTwin() {
        let legit = network(bssid: "AA:BB:CC:DD:EE:01", security: "WPA2 Personal", signal: -60)
        let twin = network(bssid: "AA:BB:CC:DD:EE:02", security: "Open", signal: -40)

        let report = SecurityWatchEvaluator.evaluate(networks: [legit, twin])
        let alert = report.alerts.first { $0.kind == .evilTwin }
        XCTAssertEqual(alert?.bssid, "AA:BB:CC:DD:EE:02")
        XCTAssertEqual(alert?.severity, .critical)
        XCTAssertEqual(report.criticalCount, 1)
    }

    func testConsistentSecurityAcrossBandsIsNotAnAlert() {
        let radios = [
            network(bssid: "AA:BB:CC:DD:EE:01", security: "WPA2/WPA3", band: .band24),
            network(bssid: "AA:BB:CC:DD:EE:02", security: "WPA2/WPA3", band: .band5),
            network(bssid: "AA:BB:CC:DD:EE:03", security: "WPA2/WPA3", band: .band6),
        ]
        XCTAssertTrue(SecurityWatchEvaluator.evaluate(networks: radios).alerts.isEmpty)
    }

    func testWPA2BesideWPA3IsNotAnAlert() {
        let wpa3 = network(bssid: "AA:BB:CC:DD:EE:01", security: "WPA3 Personal")
        let wpa2 = network(bssid: "AA:BB:CC:DD:EE:02", security: "WPA2 Personal")
        XCTAssertTrue(SecurityWatchEvaluator.evaluate(networks: [wpa3, wpa2]).alerts.isEmpty)
    }

    func testLegacyWPAOnSameSSIDIsDowngradeWarning() {
        let modern = network(bssid: "AA:BB:CC:DD:EE:01", security: "WPA2 Personal")
        let legacy = network(bssid: "AA:BB:CC:DD:EE:02", security: "WPA Personal")

        let report = SecurityWatchEvaluator.evaluate(networks: [modern, legacy])
        XCTAssertEqual(report.alerts.first?.kind, .securityDowngrade)
        XCTAssertEqual(report.alerts.first?.severity, .warning)
        XCTAssertEqual(report.alerts.first?.bssid, "AA:BB:CC:DD:EE:02")
    }

    func testRandomizedBSSIDNextToRegisteredHardwareIsFlagged() {
        let legit = network(bssid: "A4:11:22:33:44:01", security: "WPA2 Personal")
        let randomized = network(bssid: "02:AA:BB:CC:DD:EE", security: "WPA2 Personal")

        let report = SecurityWatchEvaluator.evaluate(networks: [legit, randomized])
        let alert = report.alerts.first { $0.kind == .randomizedBSSID }
        XCTAssertEqual(alert?.bssid, "02:AA:BB:CC:DD:EE")
        XCTAssertEqual(alert?.severity, .warning)
    }

    func testSSIDWithOnlyRandomizedAddressesIsNotFlagged() {
        let onlyRandom = network(bssid: "02:AA:BB:CC:DD:EE", security: "WPA2 Personal")
        XCTAssertTrue(SecurityWatchEvaluator.evaluate(networks: [onlyRandom]).alerts.isEmpty)
    }

    func testRecentDeauthBurstBecomesCriticalAlert() {
        let now = Date(timeIntervalSince1970: 1_000)
        let event = MonitorEvent(
            at: now.addingTimeInterval(-60), kind: .deauthBurst,
            bssid: "AA:BB:CC:DD:EE:09", ssid: "Corp",
            detail: "12 deauth/disassoc frames in a burst")

        let report = SecurityWatchEvaluator.evaluate(networks: [], events: [event], now: now)
        XCTAssertEqual(report.alerts.first?.kind, .deauthBurst)
        XCTAssertEqual(report.alerts.first?.severity, .critical)
        XCTAssertEqual(report.alerts.first?.detail, event.detail)
    }

    func testStaleDeauthBurstIsIgnored() {
        let now = Date(timeIntervalSince1970: 10_000)
        let event = MonitorEvent(
            at: now.addingTimeInterval(-SecurityWatchEvaluator.deauthWindow - 1),
            kind: .deauthBurst, bssid: "AA:BB:CC:DD:EE:09", ssid: "Corp",
            detail: "old burst")
        XCTAssertTrue(SecurityWatchEvaluator.evaluate(networks: [], events: [event], now: now).alerts.isEmpty)
    }

    func testHiddenSSIDIsIgnored() {
        let hidden = network(ssid: "", bssid: "AA:BB:CC:DD:EE:01", security: "Open")
        XCTAssertTrue(SecurityWatchEvaluator.evaluate(networks: [hidden]).alerts.isEmpty)
    }
}
