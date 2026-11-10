import XCTest

final class LANScannerTests: XCTestCase {

    func testARPOutputParsing() {
        let output = """
            ? (192.168.1.1) at 3c:22:fb:11:22:33 on en0 ifscope [ethernet]
            ? (192.168.1.10) at AA:BB:CC:DD:EE:01 on en0 ifscope [ethernet]
            ? (192.168.1.50) at (incomplete) on en0 ifscope [ethernet]
            ? (192.168.1.60) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
            garbage line
            """
        let entries = ARPParser.parse(output)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].ip, "192.168.1.1")
        XCTAssertEqual(entries[0].mac, "3C:22:FB:11:22:33")
        XCTAssertEqual(entries[1].mac, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(
            ARPParser.normalizedMAC("0:11:32:30:62:49"), "00:11:32:30:62:49")
    }

    func testSubnetHosts() {
        XCTAssertEqual(LANSubnet.hosts(address: "192.168.1.10", prefixLength: 24).count, 254)
        XCTAssertEqual(
            LANSubnet.hosts(address: "192.168.1.10", prefixLength: 30),
            ["192.168.1.9", "192.168.1.10"]
        )
        XCTAssertEqual(
            LANSubnet.hosts(address: "192.168.1.10", prefixLength: 31),
            ["192.168.1.10", "192.168.1.11"]
        )
        XCTAssertEqual(LANSubnet.hosts(address: "10.0.0.1", prefixLength: 8, limit: 10).count, 10)
    }

    func testAssemblerMergesProbesAndSortsGatewayFirst() {
        let entries = [
            ARPEntry(ip: "192.168.1.10", mac: "AA:BB:CC:DD:EE:01"),
            ARPEntry(ip: "192.168.1.1", mac: "AA:BB:CC:DD:EE:02"),
        ]
        let probes = [
            "192.168.1.10": [
                PortScanResult(port: 80, state: .open, responseMilliseconds: 4.2),
                PortScanResult(port: 22, state: .closed, responseMilliseconds: 1.0),
            ],
            "192.168.1.1": [
                PortScanResult(port: 443, state: .open, responseMilliseconds: 2.1)
            ],
        ]
        let devices = LANDeviceAssembler.assemble(
            entries: entries,
            hostnames: ["192.168.1.10": "nas.local"],
            probes: probes,
            gateway: "192.168.1.1",
            thisMAC: "AA:BB:CC:DD:EE:01",
            knownMACs: ["AA:BB:CC:DD:EE:01"],
            vendorFor: { _ in "Test Vendor" }
        )

        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices[0].isGateway)
        XCTAssertEqual(devices[0].ip, "192.168.1.1")
        XCTAssertEqual(devices[0].openPorts, [443])

        XCTAssertEqual(devices[1].hostname, "nas.local")
        XCTAssertEqual(devices[1].openPorts, [80])
        XCTAssertEqual(devices[1].latencyMilliseconds ?? 0, 1.0, accuracy: 0.001)
        XCTAssertTrue(devices[1].isThisMac)
        XCTAssertFalse(devices[1].isNew)

        let new = LANDeviceAssembler.assemble(
            entries: entries,
            hostnames: [:],
            probes: [:],
            gateway: nil,
            thisMAC: nil,
            knownMACs: ["AA:BB:CC:DD:EE:01"],
            vendorFor: { _ in "Test Vendor" }
        )
        XCTAssertEqual(new.filter(\.isNew).count, 1)
        XCTAssertEqual(LANGuard.newDevices(in: new, knownMACs: ["AA:BB:CC:DD:EE:01"]).count, 1)
    }

    func testGuardStoreRoundTrip() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-guard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LANGuardStore(directory: directory)
        store.save(["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
        XCTAssertEqual(
            store.load(), ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
    }
}
