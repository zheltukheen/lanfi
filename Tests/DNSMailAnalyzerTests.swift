import XCTest

final class DNSMailAnalyzerTests: XCTestCase {

    func testHealthyMailPosture() {
        let report = DNSMailAnalyzer.analyze(
            domain: "example.com",
            mx: ["10 mail.example.com."],
            txt: ["v=spf1 include:_spf.example.com -all"],
            dmarc: ["v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"],
            dkim: ["default": ["v=DKIM1; k=rsa; p=abc"]]
        )
        XCTAssertTrue(report.hasMX)
        XCTAssertTrue(report.hasSPF)
        XCTAssertTrue(report.hasDMARC)
        XCTAssertTrue(report.hasDKIM)
        XCTAssertEqual(report.dmarc?.policy, "quarantine")
        XCTAssertEqual(report.dmarc?.rua, "mailto:dmarc@example.com")
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testMissingRecordsBecomeIssues() {
        let report = DNSMailAnalyzer.analyze(
            domain: "example.com", mx: [], txt: [], dmarc: [], dkim: [:])
        XCTAssertFalse(report.hasMX)
        XCTAssertFalse(report.hasSPF)
        XCTAssertFalse(report.hasDMARC)
        XCTAssertFalse(report.hasDKIM)
        XCTAssertEqual(report.issues.count, 4)
    }

    func testMonitorOnlyDMARCIsReported() {
        let report = DNSMailAnalyzer.analyze(
            domain: "example.com",
            mx: ["10 mail.example.com."],
            txt: ["v=spf1 -all"],
            dmarc: ["v=DMARC1; p=none"],
            dkim: ["selector1": ["v=DKIM1; p=abc"]]
        )
        XCTAssertEqual(report.dmarc?.policy, "none")
        XCTAssertTrue(report.issues.contains { $0.contains("p=none") })
    }
}
