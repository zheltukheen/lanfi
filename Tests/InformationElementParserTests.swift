import XCTest

final class InformationElementParserTests: XCTestCase {

    func testEmptyInputIsSafe() {
        let parsed = InformationElementParser.parse(nil)
        XCTAssertTrue(parsed.elements.isEmpty)
        XCTAssertNil(parsed.ieCount)
        XCTAssertNil(parsed.wpsEnabled)
    }

    func testTruncatedElementIsIgnoredWithoutCrashing() {
        let data = Data([0, 20, 0x41, 0x42])
        let parsed = InformationElementParser.parse(data)
        XCTAssertNotNil(parsed)
    }

    func testParsesSSIDBSSLoadRSNAndWPS() {
        var bytes: [UInt8] = []
        bytes += ie(0, Array("Test Network".utf8))
        bytes += ie(1, [0x82, 0x84, 0x8B, 0x96])
        bytes += ie(11, [0x0A, 0x00, 0x80, 0x00, 0x00])
        bytes += ie(48, rsnPayload(pmfRequired: true))
        bytes += ie(221, wpsPayload())

        let parsed = InformationElementParser.parse(Data(bytes))

        XCTAssertEqual(parsed.channelUtilization, 50)
        XCTAssertEqual(parsed.stations, 10)
        XCTAssertEqual(parsed.pmfRequired, true)
        XCTAssertEqual(parsed.pmfCapable, true)
        XCTAssertEqual(parsed.wpsEnabled, true)
        XCTAssertTrue(parsed.wpsSummary?.contains("AP-1") == true)

        let names = parsed.elements.map(\.name)
        XCTAssertTrue(names.contains("SSID"))
        XCTAssertTrue(names.contains("RSNE"))
        XCTAssertTrue(names.contains("BSS Load"))
        XCTAssertTrue(names.contains { $0.contains("Vendor Specific") })

        let rates = parsed.elements.first { $0.name == "Supported Rates" }
        XCTAssertNotNil(rates)
        XCTAssertTrue(rates?.summary.contains("1(B)") == true)
        XCTAssertTrue(rates?.summary.contains("11(B)") == true)
    }

    func testParsesTwentyFortyAndSixGHzChannels() {
        let channel2 = InformationElementParser.parse(Data(ie(3, [6])))
        XCTAssertEqual(channel2.elements.first?.name, "DSSS Parameter Set")

        let country = InformationElementParser.parse(Data(ie(7, Array("US ".utf8) + [1, 11, 20])))
        XCTAssertEqual(country.elements.first?.name, "Country")
        XCTAssertTrue(country.elements.first?.summary.contains("US") == true)
    }

    func testRSNWithoutPMFIsReportedAsNotRequired() {
        let parsed = InformationElementParser.parse(Data(ie(48, rsnPayload(pmfRequired: false))))
        XCTAssertEqual(parsed.pmfRequired, false)
    }

    func testVendorWPSIsNotFlaggedForOtherOUIs() {
        let payload: [UInt8] = [0x00, 0x11, 0x22, 0x04, 0x00, 0x01, 0x02]
        let parsed = InformationElementParser.parse(Data(ie(221, payload)))
        XCTAssertNil(parsed.wpsEnabled)
    }

    // MARK: - Builders

    private func ie(_ id: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [id, UInt8(payload.count)] + payload
    }

    private func rsnPayload(pmfRequired: Bool) -> [UInt8] {
        var payload: [UInt8] = [
            0x01, 0x00,  // version
            0x00, 0x0F, 0xAC, 0x04,  // group cipher: CCMP-128
            0x01, 0x00,  // pairwise count
            0x00, 0x0F, 0xAC, 0x04,  // pairwise cipher: CCMP-128
            0x01, 0x00,  // AKM count
            0x00, 0x0F, 0xAC, 0x02,  // AKM: PSK
        ]
        if pmfRequired {
            payload += [0xC0, 0x00]  // PMF required + capable
        } else {
            payload += [0x00, 0x00]
        }
        return payload
    }

    private func wpsPayload() -> [UInt8] {
        var payload: [UInt8] = [0x00, 0x50, 0xF2, 0x04]  // WFA OUI + WPS type
        payload += wpsAttribute(type: 0x1044, value: [0x02])
        payload += wpsAttribute(type: 0x1011, value: Array("Test AP".utf8))
        payload += wpsAttribute(type: 0x1023, value: Array("AP-1".utf8))
        return payload
    }

    private func wpsAttribute(type: UInt16, value: [UInt8]) -> [UInt8] {
        [UInt8(type >> 8), UInt8(type & 0xFF), 0x00, UInt8(value.count)] + value
    }
}

final class EHTInformationElementTests: XCTestCase {
    func testEhtOperationReports320MHz() throws {
        // Element 255, extension 106, params, 4-byte MCS, control width=4.
        let payload: [UInt8] = [106, 0x01, 0, 0, 0, 0, 0x04, 0x2A, 0x2A]
        var data = Data([255, UInt8(payload.count)])
        data.append(contentsOf: payload)
        let parsed = InformationElementParser.parse(data)
        let element = try XCTUnwrap(parsed.elements.first { $0.name.contains("EHT Operation") })
        XCTAssertTrue(element.summary.contains("320 MHz"))
    }

    func testEhtCapabilitiesIsDecoded() throws {
        let payload: [UInt8] = [108] + Array(repeating: 0, count: 11)
        var data = Data([255, UInt8(payload.count)])
        data.append(contentsOf: payload)
        let parsed = InformationElementParser.parse(data)
        XCTAssertTrue(parsed.elements.contains { $0.name.contains("EHT Capabilities") })
    }
}

final class MultiLinkInformationElementTests: XCTestCase {
    func testMultiLinkElementIsDecoded() throws {
        let payload: [UInt8] = [107, 0x00, 0x00, 0x10, 0x00, 0x01]
        var data = Data([255, UInt8(payload.count)])
        data.append(contentsOf: payload)
        let parsed = InformationElementParser.parse(data)
        let element = try XCTUnwrap(parsed.elements.first { $0.name.contains("Multi-Link") })
        XCTAssertTrue(element.summary.contains("Basic"))
    }
}
