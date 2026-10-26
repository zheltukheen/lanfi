import XCTest

final class DiagnosticsHistoryTests: XCTestCase {
    func testStoreRoundTripAndLimit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-diag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticsHistoryStore(directory: directory, limit: 3)
        let reports = (0..<5).map { makeReport(offset: $0) }
        store.save(reports)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.last?.id, reports.last?.id)
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testFailedReportSummaries() {
        let report = makeReport(offset: 0, status: .fail)
        XCTAssertEqual(report.overall, .fail)
        XCTAssertEqual(report.failedCount, 1)
        XCTAssertTrue(report.summary.contains("failed"))
    }

    private func makeReport(offset: Int, status: DiagnosticStatus = .pass) -> DiagnosticsReport {
        let start = Date().addingTimeInterval(Double(offset))
        let check = DiagnosticCheck(
            id: "check-\(offset)", title: "DNS resolution", category: .dns, status: status,
            value: "1 ms", detail: "ok", durationMilliseconds: 1
        )
        return DiagnosticsReport(
            id: "report-\(offset)", startedAt: start, finishedAt: start.addingTimeInterval(1),
            snapshot: .empty, checks: [check]
        )
    }
}
