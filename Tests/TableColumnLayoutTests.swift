import XCTest

/// The table used to give every column its minimum width and let a trailing
/// `Spacer` take the rest: columns huddled at the left of a half-empty card and
/// a widened column pushed the last ones out. These checks pin the width rules.
final class TableColumnLayoutTests: XCTestCase {
    func testColumnsFillTheWholeCard() {
        let widths = TableColumnLayout.widths(
            minimums: [70, 70, 70], overrides: [:], available: 600)
        XCTAssertEqual(widths.reduce(0, +), 600, accuracy: 0.01)
        XCTAssertEqual(widths, [200, 200, 200])
    }

    func testLeftoverSpaceKeepsProportions() {
        let widths = TableColumnLayout.widths(
            minimums: [200, 100], overrides: [:], available: 600)
        XCTAssertEqual(widths.reduce(0, +), 600, accuracy: 0.01)
        XCTAssertGreaterThan(widths[0], widths[1])
    }

    func testNarrowCardKeepsEveryColumnAtLeastReadable() {
        let widths = TableColumnLayout.widths(
            minimums: [70, 70, 40], overrides: [:], available: 100)
        XCTAssertEqual(widths, [70, 70, 56])
    }

    func testDraggedColumnKeepsItsWidthAndBorrowsFromTheRest() {
        let widths = TableColumnLayout.widths(
            minimums: [70, 70, 70], overrides: [0: 300], available: 600)
        XCTAssertEqual(widths[0], 300, accuracy: 0.01)
        XCTAssertEqual(widths.reduce(0, +), 600, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(widths[1], 56)
        XCTAssertGreaterThanOrEqual(widths[2], 56)
    }

    func testHandSizedColumnsBelowMinimumAreRaised() {
        // A drag cannot make a column narrower than the minimum it declares;
        // the global floor only applies to columns that declare less.
        let widths = TableColumnLayout.widths(
            minimums: [70, 70], overrides: [1: 10], available: 400)
        XCTAssertEqual(widths[1], 70, accuracy: 0.01)

        let narrow = TableColumnLayout.widths(
            minimums: [70, 20], overrides: [1: 10], available: 400)
        XCTAssertEqual(narrow[1], TableColumnLayout.minColumnWidth, accuracy: 0.01)
    }

    func testEveryColumnSizedByHandStillFillsTheCard() {
        let widths = TableColumnLayout.widths(
            minimums: [70, 70], overrides: [0: 100, 1: 100], available: 400)
        XCTAssertEqual(widths, [200, 200])
    }

    func testImpossibleWidthsAskForScrollingInsteadOfSquashing() {
        // A column dragged wider than the card cannot borrow from anything, so
        // the total stays above the available width and the table scrolls.
        let widths = TableColumnLayout.widths(
            minimums: [70, 70], overrides: [0: 900, 1: 900], available: 400)
        XCTAssertEqual(widths, [900, 900])
    }
}
