import XCTest

final class SixGHzOperationInfoTests: XCTestCase {
    func testParsesLowPowerIndoorAP() {
        // Params bit 13 set, BSS color 5, 20 MHz, regulatory info 0.
        let info = SixGHzOperationInfo.parse(elementRawHex: "24 00 20 00 05 00 00 25 00 2F 2F 00")
        XCTAssertEqual(info?.primaryChannel, 37)
        XCTAssertEqual(info?.widthMHz, 20)
        XCTAssertEqual(info?.powerMode, .lowPowerIndoor)
        XCTAssertEqual(info?.duplicateBeacon, false)
    }

    func testParsesStandardPowerEightyMHz() {
        // Control 0x0A: width bits 2 (80 MHz), regulatory info 1 (SP).
        let info = SixGHzOperationInfo.parse(elementRawHex: "24 00 20 00 05 00 00 25 0A 2F 2F 00")
        XCTAssertEqual(info?.widthMHz, 80)
        XCTAssertEqual(info?.powerMode, .standardPower)
        XCTAssertEqual(info?.summary, "6 GHz SP · ch 37 · 80 MHz")
    }

    func testReturnsNilWithoutSixGHzOperationInformation() {
        // Same element with bit 13 cleared.
        XCTAssertNil(SixGHzOperationInfo.parse(elementRawHex: "24 00 00 00 05 00 00"))
    }

    func testReturnsNilForOtherExtension() {
        XCTAssertNil(SixGHzOperationInfo.parse(elementRawHex: "23 00 20 00 05 00 00 25 0A 2F 2F 00"))
    }
}

final class ReducedNeighborReportTests: XCTestCase {
    func testParsesSixGHzNeighborWithBSSIDAndPSD() {
        // Header: type 0, count 1, length 13; class 133, channel 37; entry:
        // offset 0, BSSID, short SSID, BSS parameters, 20 MHz PSD (-1 dBm).
        let bytes: [UInt8] = [
            0x00, 0x0D, 133, 37,
            0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
            0x04, 0x03, 0x02, 0x01,
            0x10,
            0xFF,
        ]
        let neighbors = ReducedNeighborReport.parse(Data(bytes))
        XCTAssertEqual(neighbors.count, 1)
        XCTAssertEqual(neighbors.first?.bssid, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(neighbors.first?.shortSSID, 0x01020304)
        XCTAssertEqual(neighbors.first?.bssParameters, 0x10)
        XCTAssertEqual(neighbors.first?.psd20MHz, -1)
        XCTAssertEqual(neighbors.first?.isSixGHz, true)
    }

    func testSkipsTruncatedEntryWithoutCrashing() {
        let bytes: [UInt8] = [0x00, 0x0D, 133, 37, 0x00, 0xAA, 0xBB]
        XCTAssertTrue(ReducedNeighborReport.parse(Data(bytes)).isEmpty)
    }

    func testNeighborAPTBTTTypeIsIgnoredSafely() {
        XCTAssertTrue(ReducedNeighborReport.parse(Data()).isEmpty)
    }

    func testInformationElementParserSurfacesBothDecoders() {
        var data: [UInt8] = [201, 17, 0x00, 0x0D, 133, 37]
        data += [0x00, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x04, 0x03, 0x02, 0x01, 0x10, 0xFF]
        data += [255, 12, 36, 0x00, 0x20, 0x00, 0x05, 0x00, 0x00, 0x25, 0x0A, 0x2F, 0x2F, 0x00]

        let parsed = InformationElementParser.parse(Data(data))
        let rnr = parsed.elements.first { $0.elementId == 201 }
        let he = parsed.elements.first { $0.elementId == 255 && $0.name.contains("HE Operation") }

        XCTAssertEqual(rnr?.name, "Reduced Neighbor Report")
        XCTAssertEqual(rnr?.summary, "1 neighbour · 1 on 6 GHz")
        XCTAssertTrue(rnr?.detailLines.first?.contains("ch 37") == true)
        XCTAssertTrue(he?.summary.contains("SP") == true)
        XCTAssertTrue(he?.detailLines.contains { $0.contains("Standard Power") } == true)
    }
}
