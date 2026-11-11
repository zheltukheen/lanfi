import XCTest

final class DNSPropagationTests: XCTestCase {

    func testSummaryMatchesExpectedValues() {
        let results = [
            result(.cloudflare, ["8.8.8.8"], error: nil),
            result(.google, ["8.8.8.8"], error: nil),
            result(DNSResolver(id: "q", name: "Q", address: "9.9.9.9"), ["1.1.1.1"], error: nil),
        ]
        let summary = DNSPropagationSummary(expected: "8.8.8.8", results: results)
        XCTAssertEqual(summary.successfulCount, 3)
        XCTAssertEqual(summary.matchingCount, 2)
        XCTAssertFalse(summary.allMatch)
        XCTAssertFalse(summary.consistent)
    }

    func testSummaryConsistentWhenAllAnswersAgree() {
        let results = [
            result(.cloudflare, ["8.8.8.8", "8.8.4.4"], error: nil),
            result(.google, ["8.8.4.4", "8.8.8.8"], error: nil),
        ]
        let summary = DNSPropagationSummary(expected: "", results: results)
        XCTAssertTrue(summary.consistent)
        XCTAssertEqual(summary.matchingCount, 0)
        XCTAssertFalse(summary.allMatch)
    }

    func testResolverListIsUnique() {
        let ids = DNSResolver.propagation.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertGreaterThanOrEqual(ids.count, 4)
    }

    private func result(
        _ resolver: DNSResolver, _ values: [String], error: String?
    ) -> DNSPropagationResult {
        DNSPropagationResult(
            resolver: resolver,
            records: values.map {
                DNSRecord(name: "example.com", type: .a, ttl: 300, value: $0)
            },
            milliseconds: 10,
            error: error
        )
    }
}
