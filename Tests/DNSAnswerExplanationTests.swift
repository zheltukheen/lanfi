import XCTest

final class DNSAnswerExplanationTests: XCTestCase {
    func testFakeIPRangeIsReported() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("198.18.0.4", type: .a)], systemRecords: nil)
        XCTAssertEqual(notes.first?.kind, .warning)
        XCTAssertEqual(notes.first?.id, "fake-ip")
        XCTAssertTrue(notes.first?.text.contains("198.18.0.4") == true)
    }

    func testFakeIPOnlyCoversTheBenchmarkRange() {
        XCTAssertTrue(DNSAnswerExplanation.isFakeIP("198.18.0.1"))
        XCTAssertTrue(DNSAnswerExplanation.isFakeIP("198.19.255.254"))
        XCTAssertFalse(DNSAnswerExplanation.isFakeIP("198.20.0.1"))
        XCTAssertFalse(DNSAnswerExplanation.isFakeIP("192.168.1.1"))
        XCTAssertFalse(DNSAnswerExplanation.isFakeIP("not-an-address"))
    }

    func testAllPrivateAddressesAreReported() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("192.168.1.10", type: .a), record("fd00::1", type: .aaaa)],
            systemRecords: nil)
        XCTAssertTrue(notes.contains { $0.id == "private" })
    }

    func testMixedPrivateAndPublicIsNotReported() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("192.168.1.10", type: .a), record("93.184.215.14", type: .a)],
            systemRecords: nil)
        XCTAssertFalse(notes.contains { $0.id == "private" })
    }

    func testZeroTTLIsExplained() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("1.1.1.1", type: .a, ttl: 0)], systemRecords: nil)
        XCTAssertTrue(notes.contains { $0.id == "ttl-zero" })
    }

    func testSystemResolverComparison() {
        let records = [record("93.184.215.14", type: .a)]

        let same = DNSAnswerExplanation.notes(
            records: records, systemRecords: [record("93.184.215.14", type: .a)])
        XCTAssertTrue(same.contains { $0.id == "system-agrees" })

        let different = DNSAnswerExplanation.notes(
            records: records, systemRecords: [record("10.0.0.5", type: .a)])
        let note = different.first { $0.id == "system-differs" }
        XCTAssertEqual(note?.kind, .warning)
        XCTAssertTrue(note?.text.contains("10.0.0.5") == true)
    }

    func testNoSystemNoteWhenTheQuestionWasNotAskedTwice() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("93.184.215.14", type: .a)], systemRecords: nil)
        XCTAssertFalse(notes.contains { $0.id.hasPrefix("system-") })
    }

    func testSeveralNetworksReadAsAContentNetwork() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("1.1.1.1", type: .a), record("8.8.8.8", type: .a)],
            systemRecords: nil, organizations: ["Cloudflare", "Google", "Cloudflare"])
        XCTAssertTrue(notes.contains { $0.id == "cdn" })
        XCTAssertFalse(
            DNSAnswerExplanation.notes(
                records: [record("1.1.1.1", type: .a)], systemRecords: nil,
                organizations: ["Cloudflare"]
            ).contains { $0.id == "cdn" })
    }

    func testPlainPublicAnswerSaysNothing() {
        let notes = DNSAnswerExplanation.notes(
            records: [record("93.184.215.14", type: .a)], systemRecords: nil)
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - Helpers

    private func record(_ value: String, type: DNSRecordType, ttl: UInt32 = 300) -> DNSRecord {
        DNSRecord(name: "example.com", type: type, ttl: ttl, value: value)
    }
}
