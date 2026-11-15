import XCTest

final class ScanCadenceTests: XCTestCase {
    func testForegroundUsesBaseInterval() {
        let cadence = ScanCadence(
            baseInterval: 3, reduceInBackground: true, lowPowerMode: false)
        XCTAssertEqual(cadence.interval(isForeground: true), 3)
    }

    func testBackgroundSlowsToFifteenSeconds() {
        let cadence = ScanCadence(
            baseInterval: 3, reduceInBackground: true, lowPowerMode: false)
        XCTAssertEqual(cadence.interval(isForeground: false), 15)
    }

    func testLowPowerSlowsToThirtySeconds() {
        let cadence = ScanCadence(
            baseInterval: 3, reduceInBackground: true, lowPowerMode: true)
        XCTAssertEqual(cadence.interval(isForeground: false), 30)
        XCTAssertEqual(cadence.interval(isForeground: true), 30)
    }

    func testLongerBaseIntervalIsPreserved() {
        let cadence = ScanCadence(
            baseInterval: 60, reduceInBackground: true, lowPowerMode: true)
        XCTAssertEqual(cadence.interval(isForeground: false), 60)
    }

    func testReductionCanBeDisabled() {
        let cadence = ScanCadence(
            baseInterval: 3, reduceInBackground: false, lowPowerMode: true)
        XCTAssertEqual(cadence.interval(isForeground: false), 3)
    }

    func testIntervalIsCapped() {
        let cadence = ScanCadence(
            baseInterval: 1_000, reduceInBackground: true, lowPowerMode: false)
        XCTAssertEqual(cadence.interval(isForeground: false), 300)
    }
}
