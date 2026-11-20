import XCTest

final class DoTClientTests: XCTestCase {
    func testFramingAddsTheTwoByteLength() {
        let message = Data([0xAB, 0xCD, 0xEF])
        XCTAssertEqual([UInt8](DoTFraming.frame(message)), [0x00, 0x03, 0xAB, 0xCD, 0xEF])
    }

    func testPartialFrameIsKeptForTheNextRead() {
        var buffer = Data([0x00, 0x04, 0x01, 0x02])
        XCTAssertNil(DoTFraming.takeFrame(from: &buffer), "only half the message has arrived")
        XCTAssertEqual([UInt8](buffer), [0x00, 0x04, 0x01, 0x02])

        buffer.append(contentsOf: [0x03, 0x04, 0xFF])
        XCTAssertEqual([UInt8](DoTFraming.takeFrame(from: &buffer) ?? Data()), [1, 2, 3, 4])
        XCTAssertEqual([UInt8](buffer), [0xFF], "the extra byte waits for the next frame")
    }

    func testTwoFramesInOneReadAreSplit() {
        var buffer = DoTFraming.frame(Data([0x10])) + DoTFraming.frame(Data([0x20, 0x30]))
        XCTAssertEqual([UInt8](DoTFraming.takeFrame(from: &buffer) ?? Data()), [0x10])
        XCTAssertEqual([UInt8](DoTFraming.takeFrame(from: &buffer) ?? Data()), [0x20, 0x30])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testResolverParsing() {
        XCTAssertEqual(
            DoTResolver.custom("tls://dns.google"),
            DoTResolver(id: "dot:dns.google:853", name: "dns.google", host: "dns.google"))
        XCTAssertEqual(DoTResolver.custom("dns.google:8853")?.port, 8853)
        XCTAssertNil(DoTResolver.custom(""))
        XCTAssertNil(DoTResolver.custom("host:0"))
        XCTAssertNil(DoTResolver.custom("-bad"))
    }

    func testTransportRankKeepsPlainFirst() {
        XCTAssertTrue(DNSComparisonTransport.udp.rank < DNSComparisonTransport.doh.rank)
        XCTAssertTrue(DNSComparisonTransport.doh.rank < DNSComparisonTransport.dot.rank)
        XCTAssertEqual(DNSComparisonTransport.dot.label, "DoT")
    }

    // MARK: - Live probe

    /// Opt-in: `LANFI_LIVE_TESTS=1 xcodebuild test …`. Talks to a real DoT
    /// resolver so the TLS handshake, the length-prefixed framing and the wire
    /// parser are exercised together, which a recorded frame cannot show.
    func testLiveDoTLookup() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LANFI_LIVE_TESTS"] == "1",
            "Set LANFI_LIVE_TESTS=1 to query a public DoT resolver.")

        let result = try await DoTDNSClient().lookup(
            host: "example.com", type: .a, resolver: .cloudflare, timeout: 8)
        XCTAssertFalse(result.records.isEmpty, "the resolver returned no A records")
        print("DoT live probe: \(result.records.map(\.value).joined(separator: ", ")) in \(result.milliseconds) ms")
    }
}
