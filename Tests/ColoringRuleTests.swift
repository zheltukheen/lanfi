import XCTest

final class ColoringRuleTests: XCTestCase {
    func testColorHexRoundTrip() {
        let color = ColorHex.color(from: "#FF8800")!
        XCTAssertEqual(ColorHex.hex(from: color), "#FF8800")
    }

    func testRuleEvaluationUsesFilterEngine() {
        let network = makeNetwork(security: "Open", signal: -60)
        let rule = ColoringRule(name: "Open", field: .security, op: .contains, value: "open", colorHex: "#FF0000")
        let filterRule = NetworkFilterRule(field: rule.field, op: rule.op, value: rule.value)
        XCTAssertTrue(NetworkFilterEngine.evaluate(filterRule, network: network, metrics: nil, connectedBSSID: nil))
    }
}
