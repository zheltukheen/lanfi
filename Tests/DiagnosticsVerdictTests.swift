import XCTest

final class DiagnosticsVerdictTests: XCTestCase {

    func testBrokenLinkIsLocalNetwork() {
        XCTAssertEqual(report([check("wifi-link", .fail)]).verdict, .localNetwork)
        XCTAssertEqual(report([check("ipv4", .fail)]).verdict, .localNetwork)
        XCTAssertEqual(report([check("wifi-signal", .fail)]).verdict, .localNetwork)
    }

    func testUnresponsiveGatewayIsRouter() {
        XCTAssertEqual(report([check("gateway", .fail)]).verdict, .router)
    }

    func testLossPastALiveGatewayIsProvider() {
        XCTAssertEqual(
            report([check("gateway", .pass), check("latency", .fail)]).verdict, .provider)
    }

    func testDNSFailureAfterWorkingConnectionIsDNS() {
        XCTAssertEqual(
            report([
                check("gateway", .pass), check("latency", .pass), check("dns", .fail),
            ]).verdict, .dns)
    }

    func testWebFailureAfterDNSIsWeb() {
        XCTAssertEqual(
            report([
                check("gateway", .pass), check("latency", .pass), check("dns", .pass),
                check("internet", .fail),
            ]).verdict, .web)
    }

    func testEverythingPassingIsHealthy() {
        XCTAssertEqual(
            report([
                check("wifi-link", .pass), check("ipv4", .pass), check("gateway", .pass),
                check("latency", .pass), check("dns", .pass), check("internet", .pass),
            ]).verdict, .healthy)
    }

    func testWarningsDoNotOverrideAWorkingPath() {
        XCTAssertEqual(
            report([check("gateway", .warning), check("latency", .warning)]).verdict, .healthy)
    }

    func testEvidenceContainsTheDecidingChecks() {
        let report = self.report([check("gateway", .pass), check("latency", .fail)])
        XCTAssertEqual(report.verdictEvidence.map(\.id), ["gateway", "latency"])
    }

    private func report(_ checks: [DiagnosticCheck]) -> DiagnosticsReport {
        DiagnosticsReport(
            id: UUID().uuidString,
            startedAt: Date(),
            finishedAt: Date(),
            snapshot: .empty,
            checks: checks
        )
    }

    private func check(_ id: String, _ status: DiagnosticStatus) -> DiagnosticCheck {
        DiagnosticCheck(
            id: id,
            title: id,
            category: .network,
            status: status,
            value: "value",
            detail: "detail",
            durationMilliseconds: nil
        )
    }
}
