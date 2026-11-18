import XCTest

final class AccessibilityPaletteTests: XCTestCase {
    override func tearDown() {
        AccessibilityPalette.reload()
        super.tearDown()
    }

    func testEveryRoleResolvesToFiveDistinctHues() {
        let colours = AccessibilityPalette.Role.allCases.map {
            AccessibilityPalette.safeColor(for: $0)
        }
        // Quality/status/band roles intentionally share five semantic colours.
        XCTAssertEqual(Set(colours.map { "\($0.red)-\($0.green)-\($0.blue)" }).count, 5)
    }

    func testSafeQualityRolesDiffer() {
        let excellent = AccessibilityPalette.safeColor(for: .excellent)
        let good = AccessibilityPalette.safeColor(for: .good)
        let fair = AccessibilityPalette.safeColor(for: .fair)
        let poor = AccessibilityPalette.safeColor(for: .poor)
        XCTAssertNotEqual(excellent, good)
        XCTAssertNotEqual(good, fair)
        XCTAssertNotEqual(fair, poor)
        XCTAssertNotEqual(excellent, poor)
    }

    func testFlagFollowsTheDefaultsKey() {
        let suite = UserDefaults(suiteName: "LanFiTests.accessibilityPalette")!
        suite.removePersistentDomain(forName: "LanFiTests.accessibilityPalette")
        AccessibilityPalette.reload(from: suite)
        XCTAssertFalse(AccessibilityPalette.isEnabled)

        suite.set(true, forKey: AccessibilityPalette.colorBlindSafeKey)
        AccessibilityPalette.reload(from: suite)
        XCTAssertTrue(AccessibilityPalette.isEnabled)

        AccessibilityPalette.setEnabled(false)
        XCTAssertFalse(AccessibilityPalette.isEnabled)
        suite.removePersistentDomain(forName: "LanFiTests.accessibilityPalette")
    }

    /// The draw path reads the cache, not the defaults: a defaults write alone
    /// would leave the window on the old hues, so the toggle must call
    /// `setEnabled` before the redraw.
    func testDrawPathReadsTheCacheNotTheDefaults() {
        let suite = UserDefaults(suiteName: "LanFiTests.accessibilityPalette")!
        suite.removePersistentDomain(forName: "LanFiTests.accessibilityPalette")
        AccessibilityPalette.setEnabled(false)
        suite.set(true, forKey: AccessibilityPalette.colorBlindSafeKey)
        XCTAssertFalse(AccessibilityPalette.isEnabled)

        AccessibilityPalette.setEnabled(true)
        XCTAssertTrue(AccessibilityPalette.isEnabled)
        suite.removePersistentDomain(forName: "LanFiTests.accessibilityPalette")
    }
}
