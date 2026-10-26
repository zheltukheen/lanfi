import XCTest

final class DiagnosticsTests: XCTestCase {

    func testPingParserHandlesMacOSOutput() throws {
        let output = """
            PING 1.1.1.1 (1.1.1.1): 56 data bytes

            --- 1.1.1.1 ping statistics ---
            4 packets transmitted, 4 packets received, 0.0% packet loss
            round-trip min/avg/max/stddev = 8.120/9.345/11.200/1.100 ms
            """
        let result = try XCTUnwrap(PingOutputParser.parse(output))
        XCTAssertEqual(result.transmitted, 4)
        XCTAssertEqual(result.received, 4)
        XCTAssertEqual(result.packetLossPercent, 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(result.averageMilliseconds), 9.345, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(result.standardDeviationMilliseconds), 1.1, accuracy: 0.001)
    }

    func testPingParserHandlesLoss() throws {
        let output = """
            --- 8.8.8.8 ping statistics ---
            4 packets transmitted, 3 packets received, 25.0% packet loss
            round-trip min/avg/max/stddev = 20.0/30.0/40.0/8.0 ms
            """
        let result = try XCTUnwrap(PingOutputParser.parse(output))
        XCTAssertEqual(result.received, 3)
        XCTAssertEqual(result.packetLossPercent, 25, accuracy: 0.01)
    }

    func testScoringThresholds() {
        XCTAssertEqual(DiagnosticScoring.signalStatus(rssi: -50), .pass)
        XCTAssertEqual(DiagnosticScoring.signalStatus(rssi: -70), .warning)
        XCTAssertEqual(DiagnosticScoring.signalStatus(rssi: -85), .fail)
        XCTAssertEqual(DiagnosticScoring.securityStatus("WPA3 Personal"), .pass)
        XCTAssertEqual(DiagnosticScoring.securityStatus("WPA2 Personal"), .warning)
        XCTAssertEqual(DiagnosticScoring.securityStatus("Open"), .fail)
        XCTAssertEqual(DiagnosticScoring.latencyStatus(nil), .fail)
        XCTAssertEqual(
            DiagnosticScoring.overall([
                check(status: .pass),
                check(status: .warning),
            ]),
            .warning
        )
        XCTAssertEqual(
            DiagnosticScoring.overall([
                check(status: .pass),
                check(status: .fail),
            ]),
            .fail
        )
    }

    func testEngineBuildsFullReportWithInjectedTransport() async throws {
        let snapshot = makeSnapshot(rssi: -52, security: "WPA3 Personal")
        let transport = FakeTransport(
            ping: PingResult(
                transmitted: 4,
                received: 4,
                packetLossPercent: 0,
                minMilliseconds: 5,
                averageMilliseconds: 12,
                maxMilliseconds: 20,
                standardDeviationMilliseconds: 2
            ),
            dns: DNSResult(host: "captive.apple.com", addresses: ["17.253.144.10"], milliseconds: 24),
            http: HTTPResult(
                statusCode: 200,
                finalURL: URL(string: "https://captive.apple.com/hotspot-detect.html"),
                bodyPrefix: "<HTML><BODY>Success</BODY></HTML>",
                milliseconds: 80
            )
        )
        let engine = NetworkDiagnosticsEngine(transport: transport, snapshotProvider: { snapshot })
        let report = await engine.run()

        XCTAssertEqual(report.overall, .pass)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertFalse(report.checks.isEmpty)
        XCTAssertTrue(report.checks.contains { $0.id == "gateway" && $0.status == .pass })
        XCTAssertTrue(report.checks.contains { $0.id == "dns" && $0.status == .pass })
        XCTAssertTrue(report.checks.contains { $0.id == "internet" && $0.status == .pass })
        XCTAssertTrue(report.checks.contains { $0.id == "wifi-signal" && $0.status == .pass })
    }

    func testEngineReportsOfflineNetwork() async {
        let snapshot = LinkSnapshot(
            interfaceName: "en0",
            ssid: nil,
            bssid: nil,
            powerOn: true,
            serviceActive: false,
            rssi: nil,
            noise: nil,
            snr: nil,
            transmitRateMbps: nil,
            channel: nil,
            band: nil,
            widthMHz: nil,
            security: nil,
            ipv4Addresses: [],
            ipv6Addresses: [],
            router: nil,
            dnsServers: []
        )
        let engine = NetworkDiagnosticsEngine(
            transport: FakeTransport(ping: nil, dns: nil, http: nil),
            snapshotProvider: { snapshot }
        )
        let report = await engine.run()
        XCTAssertEqual(report.overall, .fail)
        XCTAssertTrue(report.checks.contains { $0.id == "wifi-link" && $0.status == .fail })
        XCTAssertTrue(report.checks.contains { $0.id == "ipv4" && $0.status == .fail })
        XCTAssertTrue(report.checks.contains { $0.id == "dns" && $0.status == .fail })
    }

    // MARK: - Fixtures

    private func makeSnapshot(rssi: Int, security: String) -> LinkSnapshot {
        LinkSnapshot(
            interfaceName: "en0",
            ssid: "Test Wi-Fi",
            bssid: "00:1A:2B:11:22:33",
            powerOn: true,
            serviceActive: true,
            rssi: rssi,
            noise: -95,
            snr: rssi + 95,
            transmitRateMbps: 866,
            channel: 36,
            band: "5 GHz",
            widthMHz: 80,
            security: security,
            ipv4Addresses: ["192.168.1.42"],
            ipv6Addresses: ["fe80::1"],
            router: "192.168.1.1",
            dnsServers: ["192.168.1.1"]
        )
    }

    private func check(status: DiagnosticStatus) -> DiagnosticCheck {
        DiagnosticCheck(
            id: UUID().uuidString,
            title: "Test",
            category: .link,
            status: status,
            value: "-",
            detail: "",
            durationMilliseconds: nil
        )
    }
}

private struct FakeTransport: DiagnosticsTransport {
    let pingResult: PingResult?
    let dnsResult: DNSResult?
    let httpResult: HTTPResult?

    init(ping: PingResult?, dns: DNSResult?, http: HTTPResult?) {
        self.pingResult = ping
        self.dnsResult = dns
        self.httpResult = http
    }

    func ping(host: String, count: Int) async -> PingResult? { pingResult }
    func resolve(host: String) async -> DNSResult? { dnsResult }
    func httpCheck(url: URL) async -> HTTPResult? { httpResult }
}
