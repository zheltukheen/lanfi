import XCTest

final class SystemInterfaceTests: XCTestCase {
    func testClassifierMapsCommonDarwinInterfaces() {
        XCTAssertEqual(InterfaceClassifier.kind(name: "en0", type: "IEEE80211", hardware: nil), .wifi)
        XCTAssertEqual(InterfaceClassifier.kind(name: "en1", type: "Ethernet", hardware: nil), .ethernet)
        XCTAssertEqual(InterfaceClassifier.kind(name: "utun3", type: nil, hardware: nil), .tunnel)
        XCTAssertEqual(InterfaceClassifier.kind(name: "bridge0", type: nil, hardware: nil), .bridge)
        XCTAssertEqual(InterfaceClassifier.kind(name: "awdl0", type: nil, hardware: nil), .awdl)
        XCTAssertEqual(InterfaceClassifier.kind(name: "lo0", type: nil, hardware: nil), .loopback)
        XCTAssertEqual(InterfaceClassifier.kind(name: "pdp_ip0", type: nil, hardware: nil), .cellular)
    }

    func testNetmaskPrefix() {
        XCTAssertEqual(InterfaceClassifier.prefixLength(netmask: "255.255.255.0"), 24)
        XCTAssertEqual(InterfaceClassifier.prefixLength(netmask: "255.255.0.0"), 16)
        XCTAssertNil(InterfaceClassifier.prefixLength(netmask: "invalid"))
    }

    func testReportGroupingAndCounts() {
        let wifi = makeInterface(name: "en0", kind: .wifi, primary: true)
        let vpn = makeInterface(name: "utun3", kind: .tunnel)
        let loopback = makeInterface(name: "lo0", kind: .loopback)
        let report = InterfacesReport(
            generatedAt: Date(), interfaces: [wifi, vpn, loopback],
            primaryInterface: "en0", dnsServers: ["1.1.1.1"], router: "192.168.1.1"
        )
        XCTAssertEqual(report.upCount, 3)
        XCTAssertEqual(report.tunnelCount, 1)
        XCTAssertEqual(report.grouped.first?.0, "Physical")
        XCTAssertEqual(report.grouped.count, 3)
    }

    func testLiveScanIncludesLoopback() throws {
        let report = SystemInterfaceScanner.scan()
        XCTAssertTrue(report.interfaces.contains { $0.bsdName == "lo0" })
        XCTAssertTrue(report.interfaces.contains { $0.kind == .loopback })
        XCTAssertFalse(report.interfaces.isEmpty)
    }

    private func makeInterface(name: String, kind: InterfaceKind, primary: Bool = false) -> SystemInterface {
        SystemInterface(
            bsdName: name, displayName: name, kind: kind, isUp: true, isRunning: true,
            isPrimary: primary, macAddress: nil, mtu: 1500, linkSpeedMbps: 1000,
            ipv4: [], ipv6: [], rxBytes: 1, txBytes: 2, rxPackets: 3, txPackets: 4,
            rxErrors: 0, txErrors: 0, ssid: nil, bssid: nil, rssi: nil, security: nil,
            dnsServers: [], router: nil
        )
    }
}
