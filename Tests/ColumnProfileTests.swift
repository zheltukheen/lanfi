import XCTest

final class ColumnProfileTests: XCTestCase {
    func testProfileStoreRoundTrip() throws {
        let suite = "LanFi.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ColumnProfileStore(defaults: defaults)
        let profile = ColumnProfile.new(name: "Compact", columns: ColumnDefinition.defaults.prefix(4).map { $0 })
        store.save([profile])
        let loaded = try XCTUnwrap(store.profiles().first)
        XCTAssertEqual(loaded.name, "Compact")
        XCTAssertEqual(loaded.columns.count, 4)
        XCTAssertEqual(loaded.id, profile.id)
    }

    func testProfileCapturesCurrentVisibilityAndWidth() throws {
        let suite = "LanFi.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var columns = ColumnDefinition.defaults
        columns[0].isVisible = false
        columns[0].width = 222
        let store = ColumnProfileStore(defaults: defaults)
        store.save([.new(name: "Custom", columns: columns)])
        let loaded = try XCTUnwrap(store.profiles().first)
        XCTAssertFalse(loaded.columns[0].isVisible)
        XCTAssertEqual(loaded.columns[0].width, 222)
    }
}
