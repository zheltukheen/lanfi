import XCTest

final class CustomFilterTests: XCTestCase {
    func testAutomaticOpenFilter() {
        let open = makeNetwork(security: "Open", signal: -50)
        let secure = makeNetwork(security: "WPA3 Personal", signal: -50)
        let filter = CustomFilter.automatic.first { $0.id == "auto-open" }!
        XCTAssertTrue(filter.matches(open, metrics: nil, connectedBSSID: nil))
        XCTAssertFalse(filter.matches(secure, metrics: nil, connectedBSSID: nil))
    }

    func testAllAndAnyCombinators() {
        let network = makeNetwork(ssid: "Lab", security: "WPA3 Personal", signal: -80)
        let rules = [
            NetworkFilterRule(field: .ssid, op: .contains, value: "lab"),
            NetworkFilterRule(field: .signal, op: .lessThan, value: "-75"),
        ]
        XCTAssertTrue(
            CustomFilter(id: "a", name: "a", matchAll: true, rules: rules).matches(
                network, metrics: nil, connectedBSSID: nil))
        XCTAssertFalse(
            CustomFilter(
                id: "b", name: "b", matchAll: false,
                rules: [rules[0], NetworkFilterRule(field: .security, op: .contains, value: "open")]
            ).matches(network, metrics: nil, connectedBSSID: nil) == false)
    }

    func testRegexAndNumericOperators() {
        let network = makeNetwork(ssid: "AX55", channel: 36, signal: -50)
        XCTAssertTrue(
            NetworkFilterEngine.evaluate(
                NetworkFilterRule(field: .ssid, op: .matchesRegex, value: "^AX"), network: network, metrics: nil,
                connectedBSSID: nil))
        XCTAssertTrue(
            NetworkFilterEngine.evaluate(
                NetworkFilterRule(field: .channel, op: .greaterThan, value: "10"), network: network, metrics: nil,
                connectedBSSID: nil))
    }

    func testStoreIgnoresBuiltIns() {
        let suite = "LanFi.filters.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomFilterStore(defaults: defaults)
        let custom = CustomFilter(id: "custom", name: "Custom", matchAll: true, rules: [])
        store.save(CustomFilter.automatic + [custom])
        XCTAssertEqual(store.load().map(\.id), ["custom"])
    }
}
