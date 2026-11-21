import XCTest

/// The survey screen used to keep one boolean per tool (wall, room, walk,
/// predictive), so two tools could be on at once and the click order silently
/// decided which one ran. These checks keep the single-mode contract honest.
final class SurveyToolModeTests: XCTestCase {
    func testEveryPlanToolIsDistinct() {
        let titles = SurveyToolMode.allCases.map(\.title)
        let icons = SurveyToolMode.allCases.map(\.icon)
        let shorts = SurveyToolMode.allCases.map(\.shortTitle)
        XCTAssertEqual(Set(titles).count, SurveyToolMode.allCases.count)
        XCTAssertEqual(Set(icons).count, SurveyToolMode.allCases.count)
        XCTAssertEqual(Set(shorts).count, SurveyToolMode.allCases.count)
    }

    func testEveryPlanToolExplainsItself() {
        for tool in SurveyToolMode.allCases {
            XCTAssertFalse(tool.title.isEmpty, "\(tool) has no title")
            XCTAssertFalse(tool.hint.isEmpty, "\(tool) has no hint")
            XCTAssertFalse(tool.activationMessage.isEmpty, "\(tool) has no status message")
            XCTAssertFalse(tool.icon.isEmpty, "\(tool) has no icon")
        }
    }

    func testOnlyNonSamplingToolsShowACrosshair() {
        XCTAssertFalse(SurveyToolMode.sample.isDrawing)
        for tool in SurveyToolMode.allCases where tool != .sample {
            XCTAssertTrue(tool.isDrawing, "\(tool) should switch to a drawing cursor")
        }
    }

    func testRoomAndWallShareTheStructuralTint() {
        XCTAssertEqual(SurveyToolMode.wall.tone, .orange)
        XCTAssertEqual(SurveyToolMode.room.tone, .orange)
        XCTAssertEqual(SurveyToolMode.predictive.tone, .purple)
        XCTAssertEqual(SurveyToolMode.walk.tone, .green)
        XCTAssertEqual(SurveyToolMode.calibrate.tone, .cyan)
    }
}
