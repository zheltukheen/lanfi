import XCTest

final class OUIParserTests: XCTestCase {
    func testBuiltInVendorLookup() {
        XCTAssertEqual(OUIParser.vendor(for: "00:1A:2B:11:22:33"), "Apple")
        XCTAssertEqual(OUIParser.vendor(for: "b8-27-eb-00-11-22"), "Raspberry Pi Foundation")
    }

    func testLocallyAdministeredMACIsRandomised() {
        XCTAssertEqual(OUIParser.vendor(for: "02:00:00:00:00:01"), "Randomized MAC")
        XCTAssertEqual(OUIParser.vendor(for: "DA:AA:BB:CC:DD:EE"), "Randomized MAC")
    }

    func testInvalidOrEmptyBSSID() {
        XCTAssertEqual(OUIParser.vendor(for: ""), "-")
        XCTAssertEqual(OUIParser.vendor(for: "not-a-mac"), "-")
    }
}
