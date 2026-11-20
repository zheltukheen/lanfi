import XCTest

final class DNSComparisonTests: XCTestCase {
    func testParsesDoHJSONAnswers() throws {
        let json = """
            {"Status":0,"Answer":[
              {"name":"example.com.","type":1,"TTL":300,"data":"93.184.216.34"},
              {"name":"example.com.","type":1,"TTL":300,"data":"93.184.216.35"}
            ]}
            """
        let result = try DoHDNSClient.parse(
            Data(json.utf8), host: "example.com", resolverName: "Cloudflare DoH",
            milliseconds: 42)
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records.first?.name, "example.com")
        XCTAssertEqual(result.records.first?.type, .a)
        XCTAssertEqual(result.records.first?.ttl, 300)
        XCTAssertEqual(result.milliseconds, 42)
        XCTAssertEqual(result.resolver, "Cloudflare DoH")
    }

    func testParsesMXPriorityFromDoHData() throws {
        let json = """
            {"Status":0,"Answer":[
              {"name":"example.com.","type":15,"TTL":60,"data":"10 mail.example.com."}
            ]}
            """
        let result = try DoHDNSClient.parse(
            Data(json.utf8), host: "example.com", resolverName: "Google DoH", milliseconds: 1)
        XCTAssertEqual(result.records.first?.type, .mx)
        XCTAssertEqual(result.records.first?.priority, 10)
        XCTAssertEqual(result.records.first?.value, "mail.example.com")
    }

    func testNonZeroStatusIsAnError() {
        let json = #"{"Status":3}"#
        XCTAssertThrowsError(
            try DoHDNSClient.parse(
                Data(json.utf8), host: "missing.example", resolverName: "DoH", milliseconds: 1)
        ) { error in
            XCTAssertEqual(error as? DNSClientError, .serverStatus(3))
        }
    }

    func testEmptyAnswerIsNotAnError() throws {
        let result = try DoHDNSClient.parse(
            Data(#"{"Status":0}"#.utf8), host: "example.com", resolverName: "DoH",
            milliseconds: 5)
        XCTAssertTrue(result.records.isEmpty)
    }

    func testAgreementIgnoresOrderAndTTL() {
        let first = entry(name: "System", transport: .udp, values: ["b", "a"], ttl: 30)
        let second = entry(name: "Cloudflare", transport: .doh, values: ["a", "b"], ttl: 300)
        let comparison = DNSComparison(
            host: "example.com", type: .a, entries: [first, second])
        XCTAssertFalse(comparison.answersDisagree)
    }

    func testDisagreementIsDetected() {
        let first = entry(name: "System", transport: .udp, values: ["10.0.0.1"])
        let second = entry(name: "Cloudflare DoH", transport: .doh, values: ["93.184.216.34"])
        let comparison = DNSComparison(host: "example.com", type: .a, entries: [first, second])
        XCTAssertTrue(comparison.answersDisagree)
        XCTAssertEqual(comparison.failedCount, 0)
    }

    func testEmptyAnswerNextToAPopulatedOneIsADisagreement() {
        let answered = entry(name: "System", transport: .udp, values: ["10.0.0.1"])
        let empty = entry(name: "Google DoH", transport: .doh, values: [])
        XCTAssertTrue(
            DNSComparison(host: "example.com", type: .a, entries: [answered, empty])
                .answersDisagree)
    }

    func testFailedResolverIsCountedButDoesNotVote() {
        let answered = entry(name: "System", transport: .udp, values: ["10.0.0.1"])
        let failed = DNSComparisonEntry(
            id: "doh:google", name: "Google DoH", transport: .doh, records: [],
            milliseconds: 4000, failure: "timed out")
        let comparison = DNSComparison(host: "example.com", type: .a, entries: [answered, failed])
        XCTAssertEqual(comparison.failedCount, 1)
        XCTAssertFalse(comparison.answersDisagree)
    }

    func testExportTextListsEveryResolverAndTheVerdict() {
        let answered = entry(name: "System", transport: .udp, values: ["10.0.0.1"])
        let doh = entry(name: "Cloudflare DoH", transport: .doh, values: ["93.184.216.34"])
        let failed = DNSComparisonEntry(
            id: "doh:google", name: "Google DoH", transport: .doh, records: [],
            milliseconds: 4000, failure: "timed out")
        let text = DNSComparison(host: "example.com", type: .a, entries: [answered, doh, failed])
            .exportText

        XCTAssertTrue(text.contains("LanFi DNS comparison example.com · A"))
        XCTAssertTrue(text.contains("System\tUDP\t10.0.0.1"))
        XCTAssertTrue(text.contains("Cloudflare DoH\tDoH\t93.184.216.34"))
        XCTAssertTrue(text.contains("Google DoH\tDoH\t! timed out"), "failures stay in the copy")
        XCTAssertTrue(text.contains("Resolvers disagree on the answer."))
        XCTAssertTrue(text.contains("1 of 3 did not answer"))
    }

    func testExportTextOfAgreeingResolversSaysSo() {
        let first = entry(name: "System", transport: .udp, values: ["10.0.0.1"])
        let second = entry(name: "Cloudflare DoH", transport: .doh, values: ["10.0.0.1"])
        let text = DNSComparison(host: "example.com", type: .a, entries: [first, second]).exportText
        XCTAssertTrue(text.contains("All resolvers agree."))
        XCTAssertFalse(text.contains("did not answer"))
    }

    private func entry(
        name: String, transport: DNSComparisonTransport, values: [String], ttl: UInt32 = 60
    ) -> DNSComparisonEntry {
        DNSComparisonEntry(
            id: "\(transport.rawValue):\(name)", name: name, transport: transport,
            records: values.map { DNSRecord(name: "example.com", type: .a, ttl: ttl, value: $0) },
            milliseconds: 10, failure: nil)
    }
}
