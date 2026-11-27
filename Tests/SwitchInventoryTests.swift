import LanFiCore
import XCTest

final class SwitchInventoryTests: XCTestCase {

    // MARK: - SNMP walk primitives

    private func response(_ bindings: [(oid: String, value: [UInt8])]) -> [UInt8] {
        let variables = bindings.map { binding -> [UInt8] in
            let oid = SNMPBER.oid(binding.oid) ?? []
            return SNMPBER.tlv(0x30, oid + binding.value)
        }
        let pdu = SNMPBER.tlv(
            0xA2,
            SNMPBER.integer(7) + SNMPBER.integer(0) + SNMPBER.integer(0)
                + SNMPBER.tlv(0x30, variables.flatMap { $0 }))
        return SNMPBER.tlv(0x30, SNMPBER.integer(1) + SNMPBER.octetString("public") + pdu)
    }

    func testGetNextRequestUsesTheNextPdu() throws {
        let request = SNMPBER.getNextRequest(
            community: "public", oids: ["1.3.6.1.2.1.17.4.3.1.2"], requestID: 3)
        let outer = try XCTUnwrap(SNMPBER.parseTLV(request, at: 0))
        var index = 0
        var fields: [SNMPBER.TLV] = []
        while index < outer.0.body.count, let next = SNMPBER.parseTLV(outer.0.body, at: index) {
            fields.append(next.0)
            index = next.1
        }
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(fields[2].tag, 0xA1)

        let get = SNMPBER.getRequest(
            community: "public", oids: ["1.3.6.1.2.1.17.4.3.1.2"], requestID: 3)
        let getOuter = try XCTUnwrap(SNMPBER.parseTLV(get, at: 0))
        XCTAssertNotEqual(getOuter.0.body, outer.0.body)
    }

    func testVarBindsKeepAgentOrder() {
        let bytes = response([
            ("1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.7", SNMPBER.integer(3)),
            ("1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.8", SNMPBER.integer(4)),
        ])
        let bindings = SNMPBER.parseVarBinds(bytes)
        XCTAssertEqual(
            bindings.map(\.oid),
            [
                "1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.7",
                "1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.8",
            ])
        XCTAssertEqual(bindings.first?.value, .integer(3))
    }

    func testEndOfMibViewIsRecognised() {
        let bytes = response([
            ("1.3.6.1.2.1.17.4.3.1.2.2.3.4.5.6.7", SNMPBER.tlv(0x82, []))
        ])
        XCTAssertEqual(SNMPBER.parseVarBinds(bytes).first?.value, .endOfMibView)
        XCTAssertEqual(SwitchInventoryService.rawValue(.endOfMibView), SNMPRawValue.null)
    }

    // MARK: - Device inventory store

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-inventory-\(UUID().uuidString)", isDirectory: true)
    }

    func testLegacyKeyListIsAdoptedAsTrustedDevices() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = try JSONEncoder().encode(["aa:bb:cc:dd:ee:01", "AA:BB:CC:DD:EE:02"])
        try legacy.write(to: directory.appendingPathComponent("lan-guard.json"))

        let store = LANGuardStore(directory: directory)
        XCTAssertEqual(store.load(), ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
        let state = store.loadState()
        XCTAssertNotNil(state.seededAt)
        XCTAssertEqual(state.authorizedKeys, ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
    }

    func testInventoryRoundTripKeepsAuthorization() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LANGuardStore(directory: directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = DeviceInventoryState(seededAt: now)
        state.entries["AA:BB:CC:DD:EE:01"] = DeviceInventoryEntry(
            key: "AA:BB:CC:DD:EE:01", name: "nas", firstSeen: now, lastSeen: now,
            authorized: true)
        state.entries["AA:BB:CC:DD:EE:02"] = DeviceInventoryEntry(
            key: "AA:BB:CC:DD:EE:02", name: "printer", firstSeen: now, lastSeen: now)

        store.save(state)
        let loaded = store.loadState()

        XCTAssertEqual(loaded, state)
        XCTAssertEqual(loaded.authorizedKeys, ["AA:BB:CC:DD:EE:01"])
        XCTAssertEqual(store.load().count, 2)
    }

    func testKeyOnlySaveMergesIntoTheInventory() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LANGuardStore(directory: directory)

        store.save(["AA:BB:CC:DD:EE:01"])
        store.save(["AA:BB:CC:DD:EE:02"])

        XCTAssertEqual(store.load(), ["AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02"])
        XCTAssertEqual(store.loadState().authorizedKeys.count, 2)
    }
}
