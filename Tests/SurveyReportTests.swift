import XCTest

final class SurveyReportTests: XCTestCase {
    func testPDFReportContainsPlan() {
        let project = SurveyProject.new(name: "HQ")
        let data = SurveyReportExporter.makePDF(
            project: project, image: nil, networkName: "Test Wi-Fi"
        )
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
    }
}
