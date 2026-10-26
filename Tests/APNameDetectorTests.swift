import XCTest

final class APNameDetectorTests: XCTestCase {
    func testExtractsHostnameFromVendorIE() {
        let payload = Array("AP-Lobby-01".utf8)
        let hex = ([0x00, 0x11, 0x22] + payload).map { String(format: "%02X", $0) }.joined(separator: " ")
        let element = InformationElement(
            id: "vendor", elementId: 221, length: payload.count + 3,
            name: "Vendor Specific: Example", summary: "WMM", detailLines: [], rawHex: hex
        )
        XCTAssertEqual(
            APNameDetector.name(for: [element], ssid: "Corp Wi-Fi", vendor: "Example"),
            "AP-Lobby-01"
        )
    }

    func testRejectsProtocolTermsAndSSID() {
        let payload = Array("WPA3".utf8)
        let hex = payload.map { String(format: "%02X", $0) }.joined(separator: " ")
        let element = InformationElement(
            id: "vendor", elementId: 221, length: payload.count,
            name: "Vendor Specific", summary: "", detailLines: [], rawHex: hex
        )
        XCTAssertNil(APNameDetector.name(for: [element], ssid: "WPA3", vendor: "-"))
    }

    func testReturnsNilForNoVendorNames() {
        XCTAssertNil(APNameDetector.name(for: [], ssid: "Test", vendor: "-"))
    }
}
