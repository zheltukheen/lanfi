import XCTest

final class VPNGuardTests: XCTestCase {
    private let scutilSample = """
        DNS configuration

        resolver #1
          search domain[0] : lan
          nameserver[0] : 10.8.0.1
          if_index : 21 (utun3)
          flags    : Request A records, Request AAAA records, Default
          reach    : 0x00000002 (Reachable)

        resolver #2
          nameserver[0] : 192.168.1.1
          if_index : 6 (en0)
          flags    : Request A records
          reach    : 0x00000000 (Not Reachable)
        """

    // MARK: - Detection

    func testFullTunnelIsDetectedFromTheDefaultRoute() {
        let vpn = VPNDetector.detect(defaultInterface: "utun4", activeTunnels: ["utun4", "en0"])
        XCTAssertTrue(vpn.isUp)
        XCTAssertTrue(vpn.isFullTunnel)
        XCTAssertEqual(vpn.interfaceLabel, "utun4")
        XCTAssertEqual(vpn.activeTunnels, ["utun4"])
    }

    func testSplitTunnelCountsAsUp() {
        let vpn = VPNDetector.detect(defaultInterface: "en0", activeTunnels: ["en0", "ipsec0"])
        XCTAssertTrue(vpn.isUp)
        XCTAssertFalse(vpn.isFullTunnel)
        XCTAssertEqual(vpn.interfaceLabel, "ipsec0")
    }

    func testNoTunnelIsDown() {
        let vpn = VPNDetector.detect(defaultInterface: "en0", activeTunnels: ["en0", "bridge0"])
        XCTAssertFalse(vpn.isUp)
        XCTAssertEqual(vpn.activeTunnels, [])
    }

    // MARK: - Resolver parsing and DNS verdict

    func testParsesResolverBlocks() {
        let blocks = SCUtilDNSOutput.parse(scutilSample)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].nameservers, ["10.8.0.1"])
        XCTAssertEqual(blocks[0].interface, "utun3")
        XCTAssertTrue(blocks[0].isDefault)
        XCTAssertTrue(blocks[0].isTunnel)
        XCTAssertEqual(blocks[1].interface, "en0")
        XCTAssertFalse(blocks[1].isDefault)
    }

    func testResolverFromTheTunnelIsClean() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        let verdict = VPNDNSIntegrity.evaluate(vpn: vpn, blocks: SCUtilDNSOutput.parse(scutilSample))
        XCTAssertEqual(verdict.status, .ok)
        XCTAssertEqual(verdict.usedResolvers, ["10.8.0.1"])
    }

    func testSystemResolverOutsideTheTunnelIsALeak() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        let blocks = [
            DNSResolverBlock(index: 1, interface: "en0", nameservers: ["192.168.1.1"], isDefault: true),
            DNSResolverBlock(index: 2, interface: "utun3", nameservers: ["10.8.0.1"], isDefault: false),
        ]
        let verdict = VPNDNSIntegrity.evaluate(vpn: vpn, blocks: blocks)
        XCTAssertEqual(verdict.status, .leak)
        XCTAssertTrue(verdict.detail.contains("10.8.0.1"))
    }

    func testDnsVerdictIsUnknownWithoutATunnel() {
        let vpn = VPNDetector.detect(defaultInterface: "en0", activeTunnels: ["en0"])
        let verdict = VPNDNSIntegrity.evaluate(vpn: vpn, blocks: SCUtilDNSOutput.parse(scutilSample))
        XCTAssertEqual(verdict.status, .unknown)
    }

    func testDnsVerdictIsUnknownWhenTheTunnelPushesNoResolver() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        let blocks = [
            DNSResolverBlock(index: 1, interface: "en0", nameservers: ["192.168.1.1"], isDefault: true)
        ]
        XCTAssertEqual(VPNDNSIntegrity.evaluate(vpn: vpn, blocks: blocks).status, .unknown)
    }

    // MARK: - IPv6 verdict

    func testIpv6ThroughTheTunnelIsClean() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        XCTAssertEqual(
            VPNIPv6Integrity.evaluate(vpn: vpn, ipv6DefaultInterface: "utun3").status, .ok)
        XCTAssertEqual(VPNIPv6Integrity.evaluate(vpn: vpn, ipv6DefaultInterface: nil).status, .ok)
    }

    func testIpv6OutsideTheTunnelIsALeak() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        let verdict = VPNIPv6Integrity.evaluate(vpn: vpn, ipv6DefaultInterface: "en0")
        XCTAssertEqual(verdict.status, .leak)
        XCTAssertTrue(verdict.detail.contains("en0"))
    }

    func testIpv6VerdictIsUnknownWithoutATunnel() {
        let vpn = VPNDetector.detect(defaultInterface: "en0", activeTunnels: [])
        XCTAssertEqual(
            VPNIPv6Integrity.evaluate(vpn: vpn, ipv6DefaultInterface: "en0").status, .unknown)
    }

    // MARK: - Route table

    func testRouteTableFindsTheDefaultInterface() {
        let table = """
            Routing tables

            Internet:
            Destination        Gateway            Flags        Netif Expire
            default            192.168.1.1        UGScg          en0
            10.8.0.0/24        utun3              USc            utun3
            """
        XCTAssertEqual(RouteTableOutput.defaultInterface(table), "en0")
        XCTAssertNil(RouteTableOutput.defaultInterface("Destination Gateway\n127.0.0.1 127.0.0.1 UH lo0"))
    }

    func testReportSignatureAndLeakFlag() {
        let vpn = VPNDetector.detect(defaultInterface: "utun3", activeTunnels: ["utun3"])
        let report = VPNGuardReport(
            vpn: vpn,
            dns: DNSLeakVerdict(status: .leak, usedResolvers: ["1.1.1.1"], tunnelResolvers: ["10.8.0.1"]),
            ipv6: VPNIPv6Integrity.evaluate(vpn: vpn, ipv6DefaultInterface: "utun3"),
            checkedAt: nil)
        XCTAssertTrue(report.hasLeak)
        XCTAssertNotEqual(report.signature, VPNGuardReport.empty.signature)
    }

    func testAlertSettingsCoverTheVpnKinds() {
        var settings = MonitorAlertSettings()
        XCTAssertTrue(settings.isEnabled(for: .vpnDropped))
        XCTAssertTrue(settings.isEnabled(for: .vpnLeak))
        settings.vpnDrop = false
        XCTAssertFalse(settings.isEnabled(for: .vpnDropped))

        let legacy = try? JSONDecoder().decode(
            MonitorAlertSettings.self, from: Data(#"{"roamingFailure":false}"#.utf8))
        XCTAssertEqual(legacy?.vpnDrop, true)
        XCTAssertEqual(legacy?.vpnLeak, true)
    }
}
