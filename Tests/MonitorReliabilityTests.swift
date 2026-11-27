import LanFiCore
import XCTest

final class MonitorReliabilityTests: XCTestCase {
    func testNeutralEventsDoNotCostReliability() {
        XCTAssertNil(MonitorEventKind.connected.reliabilitySignal)
        XCTAssertNil(MonitorEventKind.roamed.reliabilitySignal)
        XCTAssertNil(MonitorEventKind.newAccessPoint.reliabilitySignal)

        XCTAssertEqual(MonitorEventKind.disconnected.reliabilitySignal, .disconnected)
        XCTAssertEqual(MonitorEventKind.roamingFailure.reliabilitySignal, .roamingFailure)
        XCTAssertEqual(MonitorEventKind.channelChanged.reliabilitySignal, .channelChanged)
        XCTAssertEqual(MonitorEventKind.deauthBurst.reliabilitySignal, .deauthBurst)
        XCTAssertEqual(MonitorEventKind.gatewayChanged.reliabilitySignal, .gatewayChanged)
        XCTAssertEqual(MonitorEventKind.vpnLeak.reliabilitySignal, .vpnLeak)
    }

    private func assessment(score: Int?) -> ReliabilityAssessment {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<30).map {
            ReliabilitySample(at: start.addingTimeInterval(Double($0) * 60), rssi: -60)
        }
        var result = ReliabilityAssessor.assess(
            samples: samples,
            signals: [ReliabilitySignalRecord(signal: .disconnected, at: start.addingTimeInterval(600))])
        if score == nil {
            result = ReliabilityAssessor.assess(samples: Array(samples.prefix(2)), signals: [])
        }
        return result
    }

    func testReportSummaryCarriesTheVerdict() throws {
        let summary = try XCTUnwrap(CombinedReport.ReliabilitySummary.make(assessment(score: 88)))

        XCTAssertEqual(summary.grade, ReliabilityGrade.good.title)
        XCTAssertEqual(summary.score, 88)
        XCTAssertTrue(summary.detail.contains("88"))
        XCTAssertEqual(summary.problems.map(\.title), [ReliabilitySignal.disconnected.title])
        XCTAssertEqual(summary.problems.first?.count, 1)
    }

    func testSparseHistoryHasNoSummarySectionsAndNoScore() throws {
        XCTAssertNil(CombinedReport.ReliabilitySummary.make(.empty))

        let sparse = try XCTUnwrap(
            CombinedReport.ReliabilitySummary.make(assessment(score: nil)))
        XCTAssertNil(sparse.score)
        XCTAssertEqual(sparse.grade, ReliabilityGrade.insufficient.title)
        XCTAssertTrue(sparse.detail.contains("Not enough data"))
    }

    func testReportHTMLPrintsTheReliabilitySection() throws {
        let summary = try XCTUnwrap(CombinedReport.ReliabilitySummary.make(assessment(score: 88)))
        let report = CombinedReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            branding: nil,
            networkCount: 0,
            averageQuality: 0,
            scan: [],
            survey: nil,
            findings: [],
            diagnostics: [],
            speedTests: [],
            events: [],
            reliability: summary)

        let html = CombinedReportExporter.html(for: report)
        XCTAssertTrue(html.contains("Reliability"))
        XCTAssertTrue(html.contains("Disconnections"))
    }
}
