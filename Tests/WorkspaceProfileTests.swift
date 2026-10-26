import XCTest

final class WorkspaceProfileTests: XCTestCase {
    func testStoreRoundTrip() {
        let suite = "LanFi.workspace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkspaceProfileStore(defaults: defaults)
        let filter = FilterProfile.capture(
            name: "Lab", searchText: "", band24: true, band5: true, band6: true,
            minSignal: -80, groupMode: .ssid, signalUnit: .dbm
        )
        let profile = WorkspaceProfile.new(
            name: "Lab", filter: filter, columns: ColumnDefinition.defaults,
            coloringRules: [], customFilters: [], activeFilterId: nil
        )
        store.save([profile])
        XCTAssertEqual(store.load().first?.name, "Lab")
        XCTAssertEqual(store.load().first?.columns.count, ColumnDefinition.defaults.count)
    }
}
