import XCTest

final class EHTPuncturingTests: XCTestCase {
    private func element(summary: String, details: [String]) -> InformationElement {
        InformationElement(
            id: "eht-op", elementId: 255, length: 10,
            name: "Extension: EHT Operation", summary: summary,
            detailLines: details, rawHex: ""
        )
    }

    func testParsesPuncturedSubchannels() {
        let info = EHTPuncturing.parse(
            elements: [
                element(
                    summary: "EHT Operation · 80 MHz · punctured 1,3",
                    details: [
                        "EHT Operation channel width 80 MHz",
                        "Channel center segment 0: 42",
                        "Punctured subchannels: 1, 3 (of 4)",
                    ]
                )
            ]
        )
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.widthCode, 2)
        XCTAssertEqual(info?.validSubchannelCount, 4)
        XCTAssertEqual(info?.puncturedSubchannels, [1, 3])
    }

    func testAbsentBitmapParsesAsNoPuncturing() {
        let info = EHTPuncturing.parse(
            elements: [element(summary: "EHT Operation · 80 MHz", details: [])]
        )
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.puncturedSubchannels, [])
        XCTAssertFalse(info?.bitmapPresent ?? true)
    }

    func testMissingElementReturnsNil() {
        XCTAssertNil(EHTPuncturing.parse(elements: []))
    }
}
