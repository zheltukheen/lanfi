import XCTest

final class ProximityBeaconTests: XCTestCase {
    func testParsesIBeaconVendorIE() {
        let bytes: [UInt8] =
            [0x4C, 0x00, 0x02, 0x15]
            + Array(0..<16).map(UInt8.init)
            + [0x00, 0x01, 0x00, 0x02, 0xC5]
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let element = InformationElement(
            id: "ibeacon", elementId: 221, length: bytes.count,
            name: "Vendor Specific", summary: "Apple", detailLines: [], rawHex: hex
        )
        let beacon = ProximityBeaconInfo.parse(element)
        XCTAssertEqual(beacon?.major, 1)
        XCTAssertEqual(beacon?.minor, 2)
        XCTAssertEqual(beacon?.uuid, "00010203-0405-0607-0809-0A0B0C0D0E0F")
    }
}
