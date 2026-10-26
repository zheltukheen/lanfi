import XCTest

final class TechnicalLocalizerTests: XCTestCase {
    func testTranslatesStatusPhrases() {
        let result = TechnicalLocalizer.localize("Security mode: WPA3 Transition · Required · Signal -52 dBm")
        XCTAssertTrue(result.contains("Требуется"))
        XCTAssertTrue(result.contains("-52 дБм"))
        XCTAssertTrue(result.contains("WPA3 Transition"))
    }

    func testLeavesBSSIDAndSSIDUntouched() {
        let value = "AA:BB:CC:DD:EE:FF · My Open Network"
        let result = TechnicalLocalizer.localize(value)
        XCTAssertTrue(result.contains("AA:BB:CC:DD:EE:FF"))
        XCTAssertTrue(result.contains("My Open Network"))
    }
}
