import XCTest

final class DNSAddressAnnotationTests: XCTestCase {
    func testSummaryKeepsTheAvailableParts() {
        let full = DNSAddressAnnotation(
            address: "142.250.74.46", country: "United States", countryCode: "US", asn: 15169,
            organization: "Google LLC")
        XCTAssertEqual(full.summary, "🇺🇸 US · AS15169 · Google LLC")

        let bare = DNSAddressAnnotation(
            address: "10.0.0.1", country: "", countryCode: "", asn: nil, organization: "")
        XCTAssertEqual(bare.summary, "—")

        let countryOnly = DNSAddressAnnotation(
            address: "1.1.1.1", country: "Australia", countryCode: "AU", asn: nil, organization: "Cloudflare")
        XCTAssertEqual(countryOnly.summary, "🇦🇺 AU · Cloudflare")
    }

    func testReportAnnotationUsesTheAsnAndFallsBackToTheIsp() {
        let report = GeoIPReport(
            query: "example.com", ip: "93.184.215.14", type: "IPv4", continent: "North America",
            country: "United States", countryCode: "US", flag: "🇺🇸", region: "California",
            city: "Los Angeles", latitude: 34.05, longitude: -118.24, asn: 15133,
            organization: "", isp: "Edgecast", timezone: "America/Los_Angeles", utcOffset: "-08:00")
        let annotation = DNSAddressAnnotation(report: report)
        XCTAssertEqual(annotation.address, "93.184.215.14")
        XCTAssertEqual(annotation.summary, "🇺🇸 US · AS15133 · Edgecast")
    }

    func testFlagForUnknownCodes() {
        XCTAssertEqual(DNSAddressAnnotation.flag(for: "US"), "🇺🇸")
        XCTAssertEqual(DNSAddressAnnotation.flag(for: ""), "")
        XCTAssertEqual(DNSAddressAnnotation.flag(for: "USA"), "")
    }

    // MARK: - Enricher

    func testEnricherDeduplicatesAndSkipsRecordsWithoutAddresses() async {
        let recorder = AddressRecorder()
        let enricher = DNSAddressEnricher(
            lookup: { address in
                await recorder.record(address)
                return Self.report(address: address)
            }, limit: 4)
        let records = [
            DNSRecord(name: "a.example", type: .a, ttl: 60, value: "1.1.1.1"),
            DNSRecord(name: "a.example", type: .a, ttl: 60, value: "1.1.1.1"),
            DNSRecord(name: "b.example", type: .a, ttl: 60, value: "8.8.8.8"),
            DNSRecord(name: "example", type: .txt, ttl: 60, value: "v=spf1 -all"),
            DNSRecord(name: "c.example", type: .a, ttl: 60, value: "not-an-address"),
        ]
        let annotations = await enricher.annotations(for: records)

        XCTAssertEqual(Set(annotations.keys), ["1.1.1.1", "8.8.8.8"])
        let asked = await recorder.addresses
        XCTAssertEqual(asked.sorted(), ["1.1.1.1", "8.8.8.8"])
    }

    func testEnricherStopsAtTheLimit() async {
        let recorder = AddressRecorder()
        let enricher = DNSAddressEnricher(
            lookup: { address in
                await recorder.record(address)
                return Self.report(address: address)
            }, limit: 2)
        let records = (1...5).map {
            DNSRecord(name: "a.example", type: .a, ttl: 60, value: "10.0.0.\($0)")
        }
        let annotations = await enricher.annotations(for: records)

        XCTAssertEqual(annotations.count, 2)
        let asked = await recorder.addresses
        XCTAssertEqual(asked.count, 2)
    }

    func testFailedLookupsLeaveTheAddressOut() async {
        let enricher = DNSAddressEnricher(
            lookup: { _ in throw GeoIPError.invalidResponse }, limit: 4)
        let records = [DNSRecord(name: "a.example", type: .a, ttl: 60, value: "1.1.1.1")]
        let annotations = await enricher.annotations(for: records)
        XCTAssertTrue(annotations.isEmpty)
    }

    // MARK: - Helpers

    private actor AddressRecorder {
        private(set) var addresses: [String] = []
        func record(_ address: String) { addresses.append(address) }
    }

    private static func report(address: String) -> GeoIPReport {
        GeoIPReport(
            query: address, ip: address, type: "IPv4", continent: "Europe", country: "Germany",
            countryCode: "DE", flag: "🇩🇪", region: "", city: "", latitude: 0, longitude: 0,
            asn: 3320, organization: "Deutsche Telekom", isp: "", timezone: "", utcOffset: "")
    }

    // MARK: - Live probe

    /// Opt-in: `LANFI_LIVE_TESTS=1 xcodebuild test …`. Proves the GeoIP service
    /// and the annotation formatting agree on a real address.
    func testLiveAnnotationForAPublicAddress() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LANFI_LIVE_TESTS"] == "1",
            "Set LANFI_LIVE_TESTS=1 to ask the GeoIP service.")

        let records = [DNSRecord(name: "example.com", type: .a, ttl: 60, value: "1.1.1.1")]
        let annotations = await DNSAddressEnricher().annotations(for: records)
        let annotation = try XCTUnwrap(annotations["1.1.1.1"])
        print("Live annotation: \(annotation.summary)")
        XCTAssertFalse(annotation.countryCode.isEmpty)
        XCTAssertNotNil(annotation.asn)
    }
}
