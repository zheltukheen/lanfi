import XCTest

final class SignalBarMetricsTests: XCTestCase {
    func testNarrowColumnKeepsTheBarAtItsMinimum() {
        // A 44 pt column with a "‑67" figure: only the minimum bar fits.
        XCTAssertEqual(
            SignalBarMetrics.barWidth(columnWidth: 44, textWidth: 24),
            SignalBarMetrics.minimumWidth)
    }

    func testWideColumnGrowsTheBar() {
        let narrow = SignalBarMetrics.barWidth(columnWidth: 90, textWidth: 24)
        let wide = SignalBarMetrics.barWidth(columnWidth: 240, textWidth: 24)
        XCTAssertGreaterThan(wide, narrow)
        XCTAssertEqual(wide, 240 - 24 - 5 - 6 - 6, accuracy: 0.001)
    }

    func testHugeTextNeverLetsTheBarRunUnderTheNumber() {
        // The clamped text keeps 60 % of a 120 pt column, so the bar stays in
        // the remaining 40 % minus the gutters instead of running under it.
        let width = SignalBarMetrics.barWidth(columnWidth: 120, textWidth: 400)
        XCTAssertLessThanOrEqual(width, 120 * (1 - SignalBarMetrics.maximumTextShare) + 0.001)
        XCTAssertGreaterThanOrEqual(width, SignalBarMetrics.minimumWidth)
    }

    func testUnusableMeasurementsFallBackToTheFullColumn() {
        // `intrinsicContentSize` reports -1 for a constrained label.
        XCTAssertEqual(SignalBarMetrics.clampedTextWidth(-1, columnWidth: 120), 0)
        XCTAssertEqual(
            SignalBarMetrics.barWidth(columnWidth: 120, textWidth: -1),
            120 - 5 - 6 - 6, accuracy: 0.001)
    }

    func testDegenerateColumnStillReturnsAPositiveWidth() {
        XCTAssertEqual(SignalBarMetrics.barWidth(columnWidth: 0, textWidth: 10), 12)
        XCTAssertEqual(SignalBarMetrics.barWidth(columnWidth: 8, textWidth: 10), 12)
    }
}
