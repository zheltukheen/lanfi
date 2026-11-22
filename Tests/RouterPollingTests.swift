import Foundation
import XCTest

final class SNMPTests: XCTestCase {
    func testLengthEncoding() {
        XCTAssertEqual(SNMPBER.encodeLength(0), [0])
        XCTAssertEqual(SNMPBER.encodeLength(127), [127])
        XCTAssertEqual(SNMPBER.encodeLength(128), [0x81, 128])
        XCTAssertEqual(SNMPBER.encodeLength(300), [0x82, 0x01, 0x2C])
    }

    func testOIDEncodingRoundTrips() throws {
        for oid in [
            SNMPOID.systemName, SNMPOID.interfaceInOctets, "1.3.6.1.4.1.9.1",
        ] {
            let encoded = try XCTUnwrap(SNMPBER.oid(oid))
            let parsed = try XCTUnwrap(SNMPBER.parseTLV(encoded, at: 0))
            XCTAssertEqual(SNMPBER.decodeOID(parsed.0.body), oid)
        }
    }

    func testGetRequestCarriesCommunityAndOIDs() throws {
        let request = SNMPBER.getRequest(
            community: "public", oids: [SNMPOID.systemName], requestID: 42)
        XCTAssertEqual(request.first, 0x30)
        let text = String(decoding: request, as: UTF8.self)
        XCTAssertTrue(text.contains("public"))
        let outer = try XCTUnwrap(SNMPBER.parseTLV(request, at: 0))
        XCTAssertEqual(outer.0.tag, 0x30)
    }

    func testResponseParsingReadsStringAndCounter() throws {
        let binding = SNMPBER.tlv(
            0x30,
            try XCTUnwrap(SNMPBER.oid(SNMPOID.systemName))
                + SNMPBER.octetString("home-router"))
        let counterBinding = SNMPBER.tlv(
            0x30,
            try XCTUnwrap(SNMPBER.oid(SNMPOID.interfaceInOctets))
                + SNMPBER.tlv(0x41, [0x00, 0x00, 0x01, 0x00]))
        let pdu = SNMPBER.tlv(
            0xA2,
            SNMPBER.integer(7) + SNMPBER.integer(0) + SNMPBER.integer(0)
                + SNMPBER.tlv(0x30, binding + counterBinding))
        let response = SNMPBER.tlv(
            0x30, SNMPBER.integer(1) + SNMPBER.octetString("public") + pdu)
        let values = SNMPBER.parseResponse(response)
        XCTAssertEqual(values[SNMPOID.systemName], .string("home-router"))
        XCTAssertEqual(values[SNMPOID.interfaceInOctets], .counter(256))
    }

    func testGetRequestRejectsMalformedPDU() {
        let pdu = SNMPBER.tlv(
            0xA0,
            SNMPBER.integer(1) + SNMPBER.integer(0) + SNMPBER.integer(0)
                + SNMPBER.tlv(0x30, []))
        let response = SNMPBER.tlv(
            0x30, SNMPBER.integer(1) + SNMPBER.octetString("public") + pdu)
        XCTAssertTrue(SNMPBER.parseResponse(response).isEmpty)
    }

    func testClientValidatesHostAndCommunity() {
        XCTAssertThrowsError(
            try SNMPClient.run(host: "", community: "public", oids: [], timeout: 0.1))
        XCTAssertThrowsError(
            try SNMPClient.run(host: "127.0.0.1", community: "", oids: [], timeout: 0.1))
    }
}
