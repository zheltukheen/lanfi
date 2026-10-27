import XCTest

final class MLOInfoTests: XCTestCase {
    func testParsesLinkDetails() {
        let element = InformationElement(
            id: "ml", elementId: 255, length: 10,
            name: "Extension: Multi-Link", summary: "Multi-Link",
            detailLines: [
                "AP MLD address: AA:BB:CC:DD:EE:FF",
                "Per-STA profile link IDs: 1, 2",
                "Link 1 BSSID: 11:22:33:44:55:66",
            ],
            rawHex: ""
        )
        let info = MLOInfo.parse(elements: [element], widthMHz: 320)
        XCTAssertEqual(info?.apMLD, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(info?.links.count, 2)
        XCTAssertEqual(info?.links.first(where: { $0.linkID == 1 })?.bssid, "11:22:33:44:55:66")
        XCTAssertTrue(info?.is320MHz == true)
    }
}
