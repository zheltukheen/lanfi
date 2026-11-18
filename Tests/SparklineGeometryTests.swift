import CoreGraphics
import XCTest

final class SparklineGeometryTests: XCTestCase {

    func testEmptyValuesProduceNoPoints() {
        XCTAssertTrue(SparklineGeometry.points(values: [], in: CGSize(width: 40, height: 12)).isEmpty)
    }

    func testUndrawableSizeProducesNoPoints() {
        XCTAssertTrue(
            SparklineGeometry.points(values: [1, 2], in: CGSize(width: 1, height: 12)).isEmpty)
        XCTAssertTrue(
            SparklineGeometry.points(values: [1, 2], in: CGSize(width: 40, height: 1)).isEmpty)
    }

    func testSingleValueSitsAtTheRightEdge() {
        let points = SparklineGeometry.points(
            values: [5], in: CGSize(width: 40, height: 12))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 40, accuracy: 0.001)
    }

    func testPeakTouchesTheTopInsetAndZeroSitsOnTheBaseline() {
        let size = CGSize(width: 40, height: 12)
        let points = SparklineGeometry.points(values: [10, 0], in: size)
        XCTAssertEqual(points[0].y, 1, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 11, accuracy: 0.001)
    }

    func testValuesClampIntoTheDrawableRect() {
        let size = CGSize(width: 30, height: 10)
        let points = SparklineGeometry.points(values: [-4, 50], in: size)
        XCTAssertEqual(points[0].y, size.height - 1, accuracy: 0.001)
        XCTAssertEqual(points[1].y, 1, accuracy: 0.001)
        XCTAssertTrue(points.allSatisfy { $0.x >= 0 && $0.x <= size.width })
    }

    func testXAxisIsEvenlySpaced() {
        let points = SparklineGeometry.points(
            values: [1, 2, 3], in: CGSize(width: 100, height: 20))
        XCTAssertEqual(points.map(\.x), [0, 50, 100])
    }

    func testFlatValuesDrawTheBaseline() {
        let size = CGSize(width: 20, height: 10)
        let points = SparklineGeometry.points(values: [0, 0], in: size)
        XCTAssertEqual(points.map(\.y), [size.height - 1, size.height - 1])
    }

    func testBaselineIsInsetFromTheBounds() {
        let baseline = SparklineGeometry.baseline(in: CGSize(width: 40, height: 12))
        XCTAssertEqual(baseline?.0, CGPoint(x: 0, y: 11))
        XCTAssertEqual(baseline?.1, CGPoint(x: 40, y: 11))
        XCTAssertNil(SparklineGeometry.baseline(in: CGSize(width: 0, height: 12)))
    }
}
