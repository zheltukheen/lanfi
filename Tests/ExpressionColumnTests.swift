import XCTest

final class ExpressionColumnTests: XCTestCase {
    func testEvaluatesTokens() {
        let network = makeNetwork(ssid: "Lab", channel: 36, security: "WPA3", signal: -52)
        let text = ExpressionEvaluator.evaluate(
            "{ssid} · {channel} · {signal} dBm · {security}", network: network, metrics: nil)
        XCTAssertEqual(text, "Lab · 36 · -52 dBm · WPA3")
    }

    func testStoreRoundTrip() {
        let suite = "LanFi.expr.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExpressionColumnStore(defaults: defaults)
        let column = ExpressionColumn(id: UUID(), name: "Label", template: "{ssid}")
        store.save([column])
        XCTAssertEqual(store.load(), [column])
    }
}
