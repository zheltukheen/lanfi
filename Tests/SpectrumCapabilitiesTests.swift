import XCTest

final class SpectrumCapabilitiesTests: XCTestCase {
    func testFallbackCoversThreeBands() {
        let channels = SpectrumCapabilities.fallback()
        XCTAssertTrue(channels.contains { $0.band == .band24 && $0.channel == 6 })
        XCTAssertTrue(channels.contains { $0.band == .band5 && $0.channel == 36 })
        XCTAssertTrue(channels.contains { $0.band == .band6 && $0.channel == 1 })
    }

    func testFilterProfileKeepsOtherFlag() {
        let profile = FilterProfile.capture(
            name: "x", searchText: "", band24: true, band5: true, band6: true,
            other: false, minSignal: -80, groupMode: .none, signalUnit: .dbm
        )
        XCTAssertEqual(profile.other, false)
    }
}
