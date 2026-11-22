import Foundation
import XCTest

final class DNSResolverSwitchTests: XCTestCase {
    func testServicesSkipTheHeaderAndDisabledEntries() {
        let output = """
            An asterisk (*) denotes that a network service is disabled.
            Wi-Fi
            *Thunderbolt Bridge
            Ethernet

            """
        XCTAssertEqual(DNSResolverSwitch.services(from: output), ["Wi-Fi", "Ethernet"])
    }

    func testServersParseAddressesAndDHCP() {
        XCTAssertEqual(
            DNSResolverSwitch.servers(from: "1.1.1.1\n1.0.0.1\n"), ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(
            DNSResolverSwitch.servers(
                from: "There aren't any DNS Servers set on Wi-Fi.\n"), [])
        XCTAssertEqual(DNSResolverSwitch.servers(from: ""), [])
        XCTAssertEqual(DNSResolverSwitch.servers(from: "not-an-address"), [])
        XCTAssertEqual(
            DNSResolverSwitch.servers(from: "2606:4700:4700::1111"), ["2606:4700:4700::1111"])
    }

    func testValidationRejectsEmptyHostnamesAndTooManyServers() {
        XCTAssertNotNil(DNSResolverSwitch.validate([]))
        XCTAssertNotNil(DNSResolverSwitch.validate(["dns.example.com"]))
        XCTAssertNotNil(
            DNSResolverSwitch.validate(["1.1.1.1", "1.0.0.1", "8.8.8.8", "9.9.9.9"]))
        XCTAssertNil(DNSResolverSwitch.validate(["1.1.1.1", "1.0.0.1"]))
    }

    func testCommandsQuoteTheServiceAndUseEmptyForDHCP() {
        let set = DNSResolverSwitch.setCommand(
            service: "Wi-Fi", servers: ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(
            set, "networksetup -setdnsservers 'Wi-Fi' '1.1.1.1' '1.0.0.1'")
        XCTAssertEqual(
            DNSResolverSwitch.setCommand(service: "Wi-Fi", servers: []),
            "networksetup -setdnsservers 'Wi-Fi' 'Empty'")
        XCTAssertEqual(
            DNSResolverSwitch.authorizedScript(service: "Wi-Fi", servers: []),
            "networksetup -setdnsservers 'Wi-Fi' 'Empty' && dscacheutil -flushcache && killall -HUP mDNSResponder"
        )
    }

    func testPlanSummaryNeverClaimsSilence() {
        let plan = DNSResolverPlan(
            service: "Wi-Fi", currentServers: [], newServers: ["1.1.1.1"],
            resolverName: "Cloudflare 1.1.1.1")
        XCTAssertFalse(plan.isRevertToAutomatic)
        XCTAssertTrue(plan.summary.contains("Cloudflare"))
        let revert = DNSResolverPlan(
            service: "Wi-Fi", currentServers: ["1.1.1.1"], newServers: [],
            resolverName: "previous")
        XCTAssertTrue(revert.isRevertToAutomatic)
    }

    func testBackupRoundTripsAndDistinguishesDHCP() throws {
        let backup = DNSResolverBackup(
            service: "Wi-Fi", servers: [], savedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(backup.isAutomatic)
        let data = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(DNSResolverBackup.self, from: data)
        XCTAssertEqual(decoded, backup)
    }

    func testBenchmarkResolversMapToServers() {
        XCTAssertEqual(DNSBenchmarkResolver.cloudflare.switchServers, ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(DNSBenchmarkResolver.google.switchServers, ["8.8.8.8", "8.8.4.4"])
        XCTAssertEqual(
            DNSBenchmarkResolver.quad9.switchServers, ["9.9.9.9", "149.112.112.112"])
        XCTAssertTrue(DNSBenchmarkResolver.system.switchServers.isEmpty)
        XCTAssertFalse(DNSBenchmarkResolver.system.canSwitch)
    }
}
