import XCTest

final class FilterProfileTests: XCTestCase {
    func testProfileRoundTrip() throws {
        let profile = FilterProfile.capture(
            name: "5 GHz lab", searchText: "lab", band24: false, band5: true, band6: false,
            minSignal: -70, groupMode: .ssid, signalUnit: .percent
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(FilterProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertFalse(decoded.band24)
        XCTAssertEqual(decoded.groupMode, "ssid")
    }

    func testUnknownEnumValuesDoNotBreakImport() {
        let profile = FilterProfile(
            name: "x", searchText: "", band24: true, band5: true, band6: true,
            minSignal: -90, groupMode: "Removed mode", signalUnit: "Removed unit"
        )
        XCTAssertNil(NetworkGroupMode(rawValue: profile.groupMode))
        XCTAssertNil(SignalDisplayMode(rawValue: profile.signalUnit))
    }
}
