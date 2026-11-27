import XCTest

@testable import LanFiCore

/// G15: a recorded bridge/VLAN/LLDP walk must map a MAC to the switch port and
/// VLAN it was learned on, and must not invent what the switch did not answer.
final class BridgeMIBTests: XCTestCase {
    private func bind(_ oid: String, _ value: SNMPRawValue) -> SNMPVarBind {
        SNMPVarBind(oid: oid, value: value)
    }

    func testForwardingTableMapsMACToPortAndVLAN() {
        let rows = [
            bind("1.3.6.1.2.1.17.1.4.1.2.5", .integer(105)),
            bind("1.3.6.1.2.1.17.1.4.1.2.6", .integer(106)),
            bind("1.3.6.1.2.1.31.1.1.1.1.105", .text("Gi1/0/5")),
            bind("1.3.6.1.2.1.31.1.1.1.1.106", .text("Gi1/0/6")),
            // AA:22:56:78:90:01 learned on bridge port 5 in the default table.
            bind("1.3.6.1.2.1.17.4.3.1.2.170.34.86.120.144.1", .integer(5)),
            bind("1.3.6.1.2.1.17.7.1.4.2.1.10.20", .integer(20)),
            bind("1.3.6.1.2.1.17.7.1.4.2.1.3.20", .text("office")),
            // AA:22:56:78:90:01 also appears in VLAN 20, on port 6.
            bind("1.3.6.1.2.1.17.7.1.2.2.1.2.20.170.34.86.120.144.1", .integer(6)),
            // AA:22:56:78:90:02 only in the VLAN-aware table, port 7.
            bind("1.3.6.1.2.1.17.7.1.2.2.1.2.20.170.34.86.120.144.2", .integer(7)),
        ]

        let table = BridgeMIB.decode(rows)

        XCTAssertTrue(table.hasForwardingTable)
        XCTAssertEqual(table.ports.count, 2)
        XCTAssertEqual(table.vlanNames[20], "office")

        let first = try? XCTUnwrap(table.port(forMAC: "aa:22:56:78:90:01"))
        XCTAssertEqual(first?.bridgePort, 6)
        XCTAssertEqual(first?.vlan, 20)
        XCTAssertEqual(first?.interfaceIndex, 106)
        XCTAssertEqual(first?.portName, "Gi1/0/6")
        XCTAssertEqual(first?.portLabel, "Gi1/0/6")

        let second = try? XCTUnwrap(table.port(forMAC: "AA-22-56-78-90-02"))
        XCTAssertEqual(second?.bridgePort, 7)
        XCTAssertEqual(second?.vlan, 20)
        // No dot1dBasePortIfIndex for port 7, so no name is invented.
        XCTAssertNil(second?.portName)
        XCTAssertEqual(second?.portLabel, "port 7")
    }

    func testVLANIsNilWhenOnlyBridgeMIBAnswered() throws {
        let table = BridgeMIB.decode([
            bind("1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.7", .integer(3))
        ])
        let entry = try XCTUnwrap(table.port(forMAC: "02:03:04:05:06:07"))
        XCTAssertEqual(entry.bridgePort, 3)
        XCTAssertNil(entry.vlan)
        XCTAssertTrue(table.vlanNames.isEmpty)
    }

    func testEmptyAndForeignRowsAreIgnored() {
        let table = BridgeMIB.decode([
            bind("1.3.6.1.2.1.1.5.0", .text("switch")),
            bind("1.3.6.1.2.1.17.4.3.1.2.1.2.3.4.5", .integer(3)),
        ])
        XCTAssertTrue(table.ports.isEmpty)
        XCTAssertFalse(table.hasForwardingTable)
        XCTAssertEqual(table, .empty)
    }

    func testLLDPNeighboursGroupByLocalPort() throws {
        let neighbours = LLDP.decode([
            bind("1.0.8802.1.1.2.1.4.1.1.9.0.105.1", .text("core-sw-1")),
            bind("1.0.8802.1.1.2.1.4.1.1.8.0.105.1", .text("Gi1/0/24")),
            bind("1.0.8802.1.1.2.1.4.1.1.9.0.106.1", .text("ap-lobby")),
        ])

        XCTAssertEqual(neighbours.count, 2)
        XCTAssertEqual(neighbours[0].localPort, 105)
        XCTAssertEqual(neighbours[0].label, "core-sw-1 · Gi1/0/24")
        XCTAssertEqual(neighbours[1].label, "ap-lobby")
    }

    func testInventoryExplainsTheUplinkOfAPort() {
        let table = BridgeMIB.decode([
            bind("1.3.6.1.2.1.17.1.4.1.2.5", .integer(105)),
            bind("1.3.6.1.2.1.17.4.3.1.2.170.34.86.120.144.1", .integer(5)),
        ])
        let inventory = SwitchInventory(
            bridge: table,
            neighbours: [LLDPNeighbour(localPort: 105, systemName: "core-sw-1")]
        )
        // The forwarding entry is on bridge port 5, whose ifIndex is 105.
        let entry = table.ports[0]
        XCTAssertEqual(inventory.uplinkDescription(for: entry), "core-sw-1")
        XCTAssertNil(SwitchInventory(bridge: table).uplinkDescription(for: entry))
    }

    func testMACNormalization() {
        XCTAssertEqual(BridgeMIB.normalizedMAC("aabb.ccdd.eeff"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(BridgeMIB.normalizedMAC("0:11:32:30:62:49"), "00:11:32:30:62:49")
        XCTAssertEqual(BridgeMIB.normalizedMAC("AA:BB:CC:DD:EE:01"), "AA:BB:CC:DD:EE:01")
        XCTAssertNil(BridgeMIB.normalizedMAC("AA:BB:CC:DD:EE"))
        XCTAssertNil(BridgeMIB.normalizedMAC(""))
    }
}
