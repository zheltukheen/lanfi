import XCTest

final class GatewayIntegrityTests: XCTestCase {
    private let gateway = "192.168.1.1"

    private func entry(_ ip: String, _ mac: String) -> ARPEntry {
        ARPEntry(ip: ip, mac: mac)
    }

    // MARK: - Gateway ARP

    func testLearnsGatewayMACWithoutAnAlert() {
        var watch = GatewayARPWatch()
        let change = watch.observe(
            gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])

        XCTAssertEqual(change, .learned(ip: gateway, mac: "AA:BB:CC:DD:EE:01"))
        XCTAssertFalse(change?.isSuspicious ?? true)
        XCTAssertEqual(watch.gatewayMAC, "AA:BB:CC:DD:EE:01")
    }

    func testRepeatedSampleIsQuiet() {
        var watch = GatewayARPWatch()
        watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])
        XCTAssertNil(watch.observe(gateway: gateway, entries: [entry(gateway, "aa:bb:cc:dd:ee:01")]))
        XCTAssertEqual(watch.changeCount, 0)
    }

    func testChangedMACIsSuspicious() {
        var watch = GatewayARPWatch()
        watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])

        let change = watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:02")])
        XCTAssertEqual(
            change, .changed(ip: gateway, from: "AA:BB:CC:DD:EE:01", to: "AA:BB:CC:DD:EE:02"))
        XCTAssertTrue(change?.isSuspicious ?? false)
        XCTAssertEqual(watch.changeCount, 1)
        XCTAssertEqual(watch.gatewayMAC, "AA:BB:CC:DD:EE:02")
    }

    func testMissingARPEntryIsUnknownNotAChange() {
        var watch = GatewayARPWatch()
        watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])
        XCTAssertNil(watch.observe(gateway: gateway, entries: []))
        XCTAssertEqual(watch.gatewayMAC, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(watch.changeCount, 0)
    }

    func testDifferentGatewayRelearns() {
        var watch = GatewayARPWatch()
        watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])
        XCTAssertNil(
            watch.observe(
                gateway: "10.0.0.1", entries: [entry("10.0.0.1", "BB:BB:CC:DD:EE:09")]))
        XCTAssertEqual(watch.gatewayIP, "10.0.0.1")
        XCTAssertEqual(watch.gatewayMAC, "BB:BB:CC:DD:EE:09")
        XCTAssertEqual(watch.changeCount, 0)
    }

    func testLostGatewayIsCleared() {
        var watch = GatewayARPWatch()
        watch.observe(gateway: gateway, entries: [entry(gateway, "AA:BB:CC:DD:EE:01")])

        XCTAssertEqual(watch.observe(gateway: nil, entries: []), .cleared(ip: gateway))
        XCTAssertNil(watch.gatewayIP)
        XCTAssertNil(watch.gatewayMAC)
    }

    // MARK: - Resolver integrity

    func testAgreementIsAMatch() {
        let check = ResolverIntegrity.evaluate(
            configured: ["192.168.1.1"],
            systemAnswer: ["17.253.144.10", "17.253.144.11"],
            publicAnswer: ["17.253.144.11"])
        XCTAssertEqual(check.verdict, .match)
        XCTAssertFalse(check.isMismatch)
    }

    func testDisjointAnswersAreAMismatch() {
        let check = ResolverIntegrity.evaluate(
            configured: ["192.168.1.1"],
            systemAnswer: ["10.0.0.66"],
            publicAnswer: ["17.253.144.10"])
        XCTAssertEqual(check.verdict, .mismatch)
        XCTAssertTrue(check.isMismatch)
        XCTAssertTrue(check.detail.contains(ResolverIntegrity.canaryHost))
    }

    func testEmptyAnswersAreUnknown() {
        XCTAssertEqual(
            ResolverIntegrity.evaluate(
                configured: [], systemAnswer: [], publicAnswer: ["1.2.3.4"]
            ).verdict, .unknown)
        XCTAssertEqual(
            ResolverIntegrity.evaluate(
                configured: [], systemAnswer: ["1.2.3.4"], publicAnswer: []
            ).verdict, .unknown)
    }

    func testAnswersAreNormalizedBeforeComparing() {
        let check = ResolverIntegrity.evaluate(
            configured: [],
            systemAnswer: [" 17.253.144.10 "],
            publicAnswer: ["17.253.144.10"])
        XCTAssertEqual(check.verdict, .match)
    }

    // MARK: - Monitor and Security Watch integration

    func testMonitorIngestsExternalEvents() {
        var snapshot = MonitorSnapshot.empty
        let event = MonitorEvent(
            at: Date(), kind: .gatewayChanged, bssid: "", ssid: gateway,
            detail: "Gateway MAC changed")

        XCTAssertTrue(snapshot.ingest(event: event))
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events.first?.kind, .gatewayChanged)
    }

    func testAlertSettingsCoverTheNewKinds() {
        var settings = MonitorAlertSettings()
        XCTAssertTrue(settings.isEnabled(for: .gatewayChanged))
        XCTAssertTrue(settings.isEnabled(for: .dnsMismatch))

        settings.gatewayChange = false
        XCTAssertFalse(settings.isEnabled(for: .gatewayChanged))

        let legacy = try? JSONDecoder().decode(
            MonitorAlertSettings.self, from: Data(#"{"weakSignal":false}"#.utf8))
        XCTAssertEqual(legacy?.gatewayChange, true)
        XCTAssertEqual(legacy?.dnsMismatch, true)
    }

    func testSecurityWatchSurfacesGatewayAndDNSFindings() {
        let now = Date()
        let events = [
            MonitorEvent(
                at: now, kind: .gatewayChanged, bssid: "", ssid: gateway,
                detail: "Gateway MAC changed"),
            MonitorEvent(
                at: now, kind: .dnsMismatch, bssid: "", ssid: "DNS",
                detail: "Resolver answered differently"),
            MonitorEvent(
                at: now.addingTimeInterval(-7200), kind: .gatewayChanged, bssid: "",
                ssid: gateway, detail: "Old finding"),
        ]

        let report = SecurityWatchEvaluator.evaluate(networks: [], events: events, now: now)
        XCTAssertEqual(report.alerts(for: .gatewayChanged).count, 1)
        XCTAssertEqual(report.alerts(for: .dnsMismatch).count, 1)
        XCTAssertEqual(report.alerts(for: .gatewayChanged).first?.severity, .critical)
        XCTAssertEqual(report.alerts(for: .dnsMismatch).first?.severity, .warning)
    }
}
