import XCTest

final class DoQClientTests: XCTestCase {
    func testResolverParsing() {
        XCTAssertEqual(
            DoQResolver.custom("quic://dns.adguard-dns.com"),
            DoQResolver(
                id: "doq:dns.adguard-dns.com:853", name: "dns.adguard-dns.com",
                host: "dns.adguard-dns.com"))
        XCTAssertEqual(DoQResolver.custom("dns.google")?.host, "dns.google")
        XCTAssertEqual(DoQResolver.custom("dns.google:8853")?.port, 8853)
        XCTAssertNil(DoQResolver.custom(""))
        XCTAssertNil(DoQResolver.custom("host:0"))
        XCTAssertNil(DoQResolver.custom("-bad"))
    }

    /// RFC 9250 §4.2 keeps DoT's two-octet prefix, so DoQ must reuse exactly
    /// the framing the DoT path is tested with.
    func testQueryFramingMatchesDoT() {
        let message = Data([0x12, 0x34, 0x56])
        XCTAssertEqual(DoTFraming.frame(message), Data([0x00, 0x03, 0x12, 0x34, 0x56]))
        var buffer = DoTFraming.frame(message)
        XCTAssertEqual(DoTFraming.takeFrame(from: &buffer), message)
    }

    func testTransportRankPutsDoQLast() {
        XCTAssertEqual(DNSComparisonTransport.doq.label, "DoQ")
        XCTAssertTrue(DNSComparisonTransport.dot.rank < DNSComparisonTransport.doq.rank)
        XCTAssertTrue(DNSComparisonTransport.udp.rank < DNSComparisonTransport.doq.rank)
    }

    func testBuiltInResolversAreDistinct() {
        let hosts = DoQResolver.builtIn.map(\.host)
        XCTAssertEqual(Set(hosts).count, hosts.count)
        XCTAssertTrue(DoQResolver.builtIn.allSatisfy { $0.port == 853 })
    }

    // MARK: - Live probe

    /// Opt-in: `LANFI_LIVE_TESTS=1 xcodebuild test …`. Talks to a real DoQ
    /// resolver so the QUIC handshake, ALPN and framing are exercised together.
    func testLiveDoQLookup() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LANFI_LIVE_TESTS"] == "1",
            "Set LANFI_LIVE_TESTS=1 to query a public DoQ resolver.")

        let result = try await DoQDNSClient().lookup(
            host: "example.com", type: .a, resolver: .adGuard, timeout: 8)
        XCTAssertFalse(result.records.isEmpty, "the resolver returned no A records")
        print(
            "DoQ live probe: \(result.records.map(\.value).joined(separator: ", ")) in \(result.milliseconds) ms"
        )
    }
}
