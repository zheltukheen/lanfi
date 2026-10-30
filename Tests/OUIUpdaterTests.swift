import XCTest

final class OUIUpdaterTests: XCTestCase {
    func testParsesWiresharkManufLines() {
        let text = """
            # comment
            00:1A:2B\tExample Networks
            00:1A:2B:30/28\tLong Prefix
            AC:DE:48\tPrivate
            """
        let database = OUIUpdater.parseManuf(text)
        XCTAssertEqual(database["001A2B"], "Example Networks")
        XCTAssertEqual(database["001A2B30"], "Long Prefix")
        XCTAssertEqual(database["ACDE48"], "Private")
    }

    func testCustomOverrideWinsUntilRemoved() {
        let prefix = "A1B2C3"
        OUIParser.removeOverride(prefix)
        XCTAssertTrue(OUIParser.setOverride(prefix: prefix, vendor: "Lab Vendor"))
        XCTAssertEqual(OUIParser.vendor(for: "A1:B2:C3:00:00:01"), "Lab Vendor")
        OUIParser.removeOverride(prefix)
        XCTAssertNotEqual(OUIParser.vendor(for: "A1:B2:C3:00:00:01"), "Lab Vendor")
    }

    func testAutoUpdateRequiresOptIn() {
        let now = Date()
        XCTAssertFalse(
            OUIUpdater.shouldAutoUpdate(now: now, lastUpdated: nil, isEnabled: false),
            "Disabled by default: no network call without opt-in"
        )
        XCTAssertTrue(
            OUIUpdater.shouldAutoUpdate(now: now, lastUpdated: nil, isEnabled: true)
        )
    }

    func testAutoUpdateRunsWhenDatabaseIsStale() {
        let now = Date()
        let fresh = now.addingTimeInterval(-OUIUpdater.autoUpdateInterval + 60)
        let stale = now.addingTimeInterval(-OUIUpdater.autoUpdateInterval - 60)
        XCTAssertFalse(OUIUpdater.shouldAutoUpdate(now: now, lastUpdated: fresh, isEnabled: true))
        XCTAssertTrue(OUIUpdater.shouldAutoUpdate(now: now, lastUpdated: stale, isEnabled: true))
    }
}
