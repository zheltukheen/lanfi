import XCTest

final class TLSCertificateTests: XCTestCase {

    func testExpiredCertificateIsFlagged() {
        let report = makeReport(notAfter: Date().addingTimeInterval(-86_400))
        XCTAssertTrue(report.expired)
    }

    func testCertificateExpiringWithinThirtyDaysIsFlagged() {
        let report = makeReport(notAfter: Date().addingTimeInterval(10 * 86_400))
        XCTAssertFalse(report.expired)
        XCTAssertTrue(report.expiresSoon)
    }

    func testLongLivedCertificateIsNotFlagged() {
        let report = makeReport(notAfter: Date().addingTimeInterval(200 * 86_400))
        XCTAssertFalse(report.expired)
        XCTAssertFalse(report.expiresSoon)
    }

    private func makeReport(notAfter: Date) -> TLSCertificateReport {
        TLSCertificateReport(
            host: "example.com",
            port: 443,
            certificates: [
                TLSCertificate(
                    subject: "example.com",
                    issuer: "Test CA",
                    notBefore: Date().addingTimeInterval(-86_400),
                    notAfter: notAfter
                )
            ],
            trusted: true,
            checkedAt: Date()
        )
    }
}
