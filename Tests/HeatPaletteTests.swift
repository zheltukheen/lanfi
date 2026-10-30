import XCTest

final class HeatPaletteTests: XCTestCase {
    func testRangeEndpoints() {
        let weak = HeatPalette.rgb(-90)
        XCTAssertEqual(weak.r, 0.85, accuracy: 0.01)
        XCTAssertEqual(weak.g, 0.16, accuracy: 0.01)
        let strong = HeatPalette.rgb(-40)
        XCTAssertEqual(strong.g, 0.85, accuracy: 0.01)
        XCTAssertEqual(strong.b, 0.35, accuracy: 0.01)
    }

    func testMidpointIsYellowish() {
        let mid = HeatPalette.rgb(-65.0)
        XCTAssertGreaterThan(mid.r, 0.9)
        XCTAssertGreaterThan(mid.g, 0.8)
        XCTAssertLessThan(mid.b, 0.2)
    }

    func testValuesClampOutsideRange() {
        let low = HeatPalette.rgb(-120)
        let lowRef = HeatPalette.rgb(-90)
        XCTAssertEqual(low.r, lowRef.r, accuracy: 0.0001)
        XCTAssertEqual(low.g, lowRef.g, accuracy: 0.0001)
        XCTAssertEqual(low.b, lowRef.b, accuracy: 0.0001)
        let high = HeatPalette.rgb(-20)
        let highRef = HeatPalette.rgb(-40)
        XCTAssertEqual(high.r, highRef.r, accuracy: 0.0001)
        XCTAssertEqual(high.g, highRef.g, accuracy: 0.0001)
        XCTAssertEqual(high.b, highRef.b, accuracy: 0.0001)
    }

    func testMonotonicGreenChannel() {
        var previous = -Double.greatestFiniteMagnitude
        for rssi in stride(from: -90.0, through: -40.0, by: 5.0) {
            let green = HeatPalette.rgb(rssi).g
            XCTAssertGreaterThanOrEqual(green, previous)
            previous = green
        }
    }
}

final class HeatGridCacheTests: XCTestCase {
    func testMemoizesUntilKeyChanges() {
        let cache = HeatGridCache()
        var calls = 0
        let compute: (Int, Int) -> Int? = { _, _ in
            calls += 1
            return -70
        }
        let first = cache.grid(columns: 4, rows: 3, key: "a", compute: compute)
        _ = cache.grid(columns: 4, rows: 3, key: "a", compute: compute)
        XCTAssertEqual(calls, 12)  // computed exactly once
        XCTAssertEqual(first.cells.count, 12)
        _ = cache.grid(columns: 4, rows: 3, key: "b", compute: compute)
        XCTAssertEqual(calls, 24)  // key change recomputes
    }

    func testGeometryChangeRecomputes() {
        let cache = HeatGridCache()
        var calls = 0
        let compute: (Int, Int) -> Int? = { _, _ in
            calls += 1
            return nil
        }
        _ = cache.grid(columns: 2, rows: 2, key: "a", compute: compute)
        _ = cache.grid(columns: 3, rows: 2, key: "a", compute: compute)
        XCTAssertEqual(calls, 4 + 6)
    }

    func testNilCellsArePreserved() {
        let cache = HeatGridCache()
        let grid = cache.grid(columns: 2, rows: 1, key: "a") { column, _ in
            column == 0 ? nil : -50
        }
        XCTAssertNil(grid.cells[0])
        XCTAssertEqual(grid.cells[1], -50)
    }
}
