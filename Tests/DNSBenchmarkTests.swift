import XCTest

private struct StubDNSClient: DNSLookuping {
    var milliseconds: [String: Int]
    var failing: Set<String> = []

    func lookup(
        host: String, type: DNSRecordType, resolver: DNSResolver, timeout: TimeInterval
    ) async throws -> DNSLookupResult {
        if failing.contains(resolver.name) { throw DNSClientError.timeout }
        return DNSLookupResult(
            host: host, resolver: resolver.name, records: [],
            milliseconds: milliseconds[resolver.name] ?? 10)
    }
}

final class DNSBenchmarkTests: XCTestCase {
    func testMedianIgnoresTheSlowOutlier() {
        XCTAssertEqual(DNSBenchmarkRanker.median([10, 12, 500]), 12)
        XCTAssertEqual(DNSBenchmarkRanker.median([10, 20]), 15)
        XCTAssertNil(DNSBenchmarkRanker.median([]))
    }

    func testRankingPutsAnsweredResolversFirstThenFewestFailures() {
        let answered = DNSBenchmarkResult(
            resolverID: "a", name: "A", samples: [30, 32], failures: 0)
        let fastWithFailures = DNSBenchmarkResult(
            resolverID: "b", name: "B", samples: [8], failures: 3)
        let silent = DNSBenchmarkResult(
            resolverID: "c", name: "C", samples: [], failures: 9)

        let ranked = DNSBenchmarkRanker.ranked([silent, answered, fastWithFailures])
        XCTAssertEqual(ranked.map(\.resolverID), ["b", "a", "c"])
    }

    func testReportRecommendsOnlyAResolverThatAnsweredEverything() {
        let clean = DNSBenchmarkResult(
            resolverID: "clean", name: "Clean", samples: [20], failures: 0)
        let flaky = DNSBenchmarkResult(
            resolverID: "flaky", name: "Flaky", samples: [5], failures: 1)
        let report = DNSBenchmarkReport(startedAt: Date(), results: [flaky, clean])
        XCTAssertEqual(report.fastest?.resolverID, "clean")
    }

    func testServiceMeasuresEveryResolverAndCountsFailures() async {
        let client = StubDNSClient(
            milliseconds: ["System": 30, "Cloudflare": 12, "Google": 20],
            failing: ["Quad9"])
        let service = DNSBenchmarkService(
            client: client, hosts: ["a.test", "b.test"], rounds: 2, timeout: 1)
        let report = await service.run(resolvers: DNSBenchmarkResolver.defaults)

        XCTAssertEqual(report.results.count, DNSBenchmarkResolver.defaults.count)
        let system = report.results.first { $0.id == "system" }
        XCTAssertEqual(system?.samples.count, 4)
        XCTAssertEqual(system?.medianMilliseconds, 30)
        let quad9 = report.results.first { $0.id == "quad9" }
        XCTAssertEqual(quad9?.failures, 4)
        XCTAssertNil(quad9?.medianMilliseconds)
        XCTAssertEqual(report.fastest?.id, "cloudflare")
    }
}
