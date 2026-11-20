import XCTest

final class NATProfileTests: XCTestCase {
    // MARK: - Message

    func testBindingRequestCarriesTheMagicCookie() {
        let transaction = [UInt8](repeating: 7, count: 12)
        let data = [UInt8](STUNMessage.bindingRequest(transactionID: transaction))
        XCTAssertEqual(data.count, 20)
        XCTAssertEqual(Array(data[0..<2]), [0x00, 0x01])
        XCTAssertEqual(Array(data[4..<8]), [0x21, 0x12, 0xA4, 0x42])
        XCTAssertEqual(Array(data[8..<20]), transaction)
    }

    func testParsesXORMappedIPv4() {
        let answer = response(
            attribute: 0x0020, family: 0x01,
            port: UInt16(54321) ^ 0x2112, address: [203 ^ 0x21, 0 ^ 0x12, 113 ^ 0xA4, 5 ^ 0x42])
        let endpoint = STUNMessage.mappedEndpoint(from: answer)
        XCTAssertEqual(endpoint?.address, "203.0.113.5")
        XCTAssertEqual(endpoint?.port, 54321)
    }

    func testParsesPlainMappedIPv4() {
        let answer = response(attribute: 0x0001, family: 0x01, port: 40000, address: [10, 0, 0, 7])
        XCTAssertEqual(STUNMessage.mappedEndpoint(from: answer), STUNEndpoint(address: "10.0.0.7", port: 40000))
    }

    func testRejectsNonSuccessAndGarbage() {
        XCTAssertNil(STUNMessage.mappedEndpoint(from: Data([0, 1, 0, 0])))
        var answer = response(attribute: 0x0020, family: 0x01, port: 1, address: [1, 2, 3, 4])
        answer[1] = 0x11  // 0x0111, not a binding success
        XCTAssertNil(STUNMessage.mappedEndpoint(from: answer))
    }

    // MARK: - Classification

    func testSameMappingFromTwoServersIsEndpointIndependent() {
        let probes = [
            probe("a", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
            probe("b", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
        ]
        XCTAssertEqual(NATReport.mapping(for: probes), .endpointIndependent)
    }

    func testDifferentMappingsMeanSymmetric() {
        let probes = [
            probe("a", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
            probe("b", mapped: STUNEndpoint(address: "203.0.113.5", port: 5001)),
        ]
        XCTAssertEqual(NATReport.mapping(for: probes), .addressDependent)
    }

    func testOneAnswerIsNotEnoughToClassify() {
        let probes = [probe("a", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000))]
        XCTAssertEqual(NATReport.mapping(for: probes), .unknown)
        XCTAssertTrue(probes.allSatisfy { $0.failure == nil })
    }

    func testVerdictForConeSymmetricAndBlocked() {
        let local = STUNEndpoint(address: "192.168.1.20", port: 5000)
        let cone = report(
            local: local,
            probes: [
                probe("a", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
                probe("b", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
            ])
        XCTAssertEqual(cone.verdict, .cone)
        XCTAssertTrue(cone.portPreserved, "the router kept the source port")

        let symmetric = report(
            local: STUNEndpoint(address: "192.168.1.20", port: 54321),
            probes: [
                probe("a", mapped: STUNEndpoint(address: "203.0.113.5", port: 5000)),
                probe("b", mapped: STUNEndpoint(address: "203.0.113.5", port: 5001)),
            ])
        XCTAssertEqual(symmetric.verdict, .symmetric)
        XCTAssertFalse(symmetric.portPreserved)

        let blocked = report(
            local: local,
            probes: [
                NATProbe(
                    id: "a", server: STUNEndpoint(address: "stun.example", port: 3478),
                    mapped: nil, milliseconds: nil, failure: "timeout")
            ])
        XCTAssertEqual(blocked.verdict, .blocked)
        XCTAssertNil(blocked.externalEndpoint)
    }

    func testVerdictIsDirectWhenThePublicAddressIsAlreadyLocal() {
        let local = STUNEndpoint(address: "203.0.113.5", port: 5000)
        let direct = report(
            local: local,
            probes: [
                probe("a", mapped: local),
                probe("b", mapped: local),
            ])
        XCTAssertEqual(direct.verdict, .direct)
    }

    func testEndpointParsing() {
        XCTAssertEqual(
            STUNEndpoint.parse("stun.l.google.com:19302"),
            STUNEndpoint(address: "stun.l.google.com", port: 19302))
        XCTAssertNil(STUNEndpoint.parse("stun.l.google.com"))
        XCTAssertNil(STUNEndpoint.parse("host:0"))
        XCTAssertNil(STUNEndpoint.parse("-bad:3478"))
    }

    // MARK: - Helpers

    private func probe(_ id: String, mapped: STUNEndpoint?) -> NATProbe {
        NATProbe(
            id: id, server: STUNEndpoint(address: "stun.example", port: 3478), mapped: mapped,
            milliseconds: 10, failure: nil)
    }

    private func report(local: STUNEndpoint, probes: [NATProbe]) -> NATReport {
        NATReport(
            localEndpoint: local, probes: probes, mapping: NATReport.mapping(for: probes),
            filtering: .unknown)
    }

    /// Builds a binding success with one address attribute.
    private func response(attribute: UInt16, family: UInt8, port: UInt16, address: [UInt8])
        -> Data
    {
        // Reserved byte, family, port, address: eight bytes for IPv4.
        var body: [UInt8] = [UInt8(attribute >> 8), UInt8(attribute & 0xFF), 0, 8]
        body.append(0)
        body.append(family)
        body.append(UInt8(port >> 8))
        body.append(UInt8(port & 0xFF))
        body.append(contentsOf: address)
        var data: [UInt8] = [0x01, 0x01, 0, UInt8(body.count), 0x21, 0x12, 0xA4, 0x42]
        data.append(contentsOf: [UInt8](repeating: 0, count: 12))
        data.append(contentsOf: body)
        return Data(data)
    }
}
