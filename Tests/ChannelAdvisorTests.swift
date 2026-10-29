import XCTest

final class ChannelAdvisorTests: XCTestCase {
    func testAvoidsDFSWhenCurrentChannelIsNotDFS() throws {
        let connected = makeNetwork(
            id: "connected", band: .band5, channel: 36, generation: .mode11ac,
            signal: -50,
            informationElements: [
                InformationElement(
                    id: "wps", elementId: 221, length: 20,
                    name: "Vendor Specific", summary: "WPS",
                    detailLines: ["Model: Archer AX55"], rawHex: ""
                )
            ]
        )
        let interferer = makeNetwork(id: "other", band: .band5, channel: 36, generation: .mode11ac, signal: -40)
        let report = NetworkAnalyzer.analyze(networks: [connected, interferer])
        let advice = try XCTUnwrap(
            ChannelAdvisor.advice(for: connected, report: report, allNetworks: [connected, interferer])
        )
        if let recommended = advice.recommendation {
            XCTAssertFalse(recommended.isDFS)
            XCTAssertEqual(recommended.band, .band5)
        }
        XCTAssertEqual(advice.routerModel, "Archer AX55")
    }

    func testWiFi4DoesNotGet6GHz() throws {
        let connected = makeNetwork(id: "n", band: .band6, channel: 37, generation: .mode11n, signal: -50)
        let report = NetworkAnalyzer.analyze(networks: [connected])
        XCTAssertNil(ChannelAdvisor.advice(for: connected, report: report, allNetworks: [connected]))
    }
}
