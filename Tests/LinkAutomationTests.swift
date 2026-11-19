import XCTest

final class LinkAutomationTests: XCTestCase {
    private func policy(enabled: Bool = true, paused: Bool = false) -> LinkAutomationPolicy {
        var policy = LinkAutomationPolicy()
        policy.isEnabled = enabled
        policy.isPaused = paused
        return policy
    }

    // MARK: - Edge triggering

    func testPluggingEthernetDisablesWiFiOnce() {
        var policy = policy()
        XCTAssertEqual(policy.evaluate(wiredConnected: false, wifiOn: true), nil)
        XCTAssertEqual(policy.evaluate(wiredConnected: true, wifiOn: true), .disableWiFi)
        // Steady state: no repeated writes.
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: false))
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: false))
    }

    func testUnpluggingRestoresWiFiOnlyWhenWeDisabledIt() {
        var policy = policy()
        _ = policy.evaluate(wiredConnected: false, wifiOn: true)
        XCTAssertEqual(policy.evaluate(wiredConnected: true, wifiOn: true), .disableWiFi)
        XCTAssertEqual(policy.evaluate(wiredConnected: false, wifiOn: false), .enableWiFi)
        XCTAssertNil(policy.evaluate(wiredConnected: false, wifiOn: true))
    }

    func testWiFiAlreadyOffIsLeftAlone() {
        var policy = policy()
        _ = policy.evaluate(wiredConnected: false, wifiOn: false)
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: false))
        XCTAssertNil(policy.evaluate(wiredConnected: false, wifiOn: false))
    }

    func testManualWiFiChangeWins() {
        var policy = policy()
        _ = policy.evaluate(wiredConnected: false, wifiOn: true)
        XCTAssertEqual(policy.evaluate(wiredConnected: true, wifiOn: true), .disableWiFi)
        // User turns Wi-Fi back on while docked: we stop managing it.
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: true))
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: true))
        XCTAssertNil(policy.evaluate(wiredConnected: false, wifiOn: true))
    }

    func testManualDisableWhileDockedSurvivesAReplug() {
        var policy = policy()
        _ = policy.evaluate(wiredConnected: false, wifiOn: false)
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: false))
        // User turned Wi-Fi off by hand; after unplug and re-plug we still leave it off.
        XCTAssertNil(policy.evaluate(wiredConnected: false, wifiOn: false))
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: false))
    }

    func testPauseStopsEveryAction() {
        var policy = policy(paused: true)
        _ = policy.evaluate(wiredConnected: false, wifiOn: true)
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: true))
        policy.isPaused = false
        // Resuming adopts the current state as the baseline, it does not replay it.
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: true))
        XCTAssertEqual(policy.evaluate(wiredConnected: false, wifiOn: true), nil)
    }

    func testDisabledFeatureNeverActs() {
        var policy = policy(enabled: false)
        _ = policy.evaluate(wiredConnected: false, wifiOn: true)
        XCTAssertNil(policy.evaluate(wiredConnected: true, wifiOn: true))
        policy.isEnabled = true
        XCTAssertNil(policy.evaluate(wiredConnected: false, wifiOn: true))
    }

    func testWakeReappliesTheIntent() {
        var policy = policy()
        _ = policy.evaluate(wiredConnected: false, wifiOn: false)
        XCTAssertEqual(
            policy.reapplyAfterWake(wiredConnected: true, wifiOn: true), .disableWiFi)
        XCTAssertNil(policy.reapplyAfterWake(wiredConnected: false, wifiOn: true))
    }

    // MARK: - Parsing

    func testParsesHardwarePorts() {
        let output = """
            Hardware Port: Wi-Fi
            Device: en0
            Ethernet Address: aa:bb:cc:dd:ee:ff

            Hardware Port: Ethernet
            Device: en5
            Ethernet Address: 11:22:33:44:55:66

            Hardware Port: Thunderbolt Bridge
            Device: bridge0
            """
        let ports = HardwarePortsOutput.parse(output)
        XCTAssertEqual(ports.count, 3)
        XCTAssertEqual(LinkAutomationClassifier.wifiPort(ports)?.device, "en0")
        XCTAssertEqual(
            LinkAutomationClassifier.ethernetPorts(ports).map(\.device), ["en5"])
    }

    func testClassifierExcludesWifiAndBridges() {
        let ports = [
            HardwarePort(name: "Wi-Fi", device: "en0"),
            HardwarePort(name: "Ethernet", device: "en7"),
            HardwarePort(name: "Bridge", device: "bridge1"),
            HardwarePort(name: "VPN", device: "utun4"),
        ]
        XCTAssertEqual(
            LinkAutomationClassifier.ethernetPorts(ports).map(\.device), ["en7"])
    }

    func testParsesWiFiPower() {
        XCTAssertEqual(AirportPowerOutput.isOn("Wi-Fi Power (en0): On"), true)
        XCTAssertEqual(AirportPowerOutput.isOn("Wi-Fi Power (en0): Off"), false)
        XCTAssertNil(AirportPowerOutput.isOn("garbage"))
    }

    func testParsesLinkStatus() {
        let active = """
            en5: flags=8863<UP,BROADCAST,SMART,RUNNING> mtu 1500
            \tstatus: active
            """
        let inactive = """
            en5: flags=8822<BROADCAST,SMART> mtu 1500
            \tstatus: inactive
            """
        XCTAssertTrue(IfconfigOutput.isActive(active))
        XCTAssertFalse(IfconfigOutput.isActive(inactive))
        XCTAssertFalse(IfconfigOutput.isActive(""))
    }
}
