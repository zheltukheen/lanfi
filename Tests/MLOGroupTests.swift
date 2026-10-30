import XCTest

final class MLOGroupTests: XCTestCase {
    private func multiLinkElement(apMLD: String, details: [String]) -> InformationElement {
        InformationElement(
            id: "ml-\(apMLD)-\(details.count)", elementId: 255, length: 10,
            name: "Extension: Multi-Link", summary: "Multi-Link · Basic",
            detailLines: ["AP MLD address: \(apMLD)"] + details,
            rawHex: ""
        )
    }

    private func beacon(
        _ bssid: String, channel: Int, rssi: Int, elements: [InformationElement]
    ) -> CapturedBeacon {
        CapturedBeacon(
            id: bssid, bssid: bssid, ssid: "Home", channel: channel, rssi: rssi,
            security: "WPA3 Personal", isEHT: true, informationElements: elements,
            clientCount: nil, timestamp: Date(), source: "pcap"
        )
    }

    func testAssemblesFullLinkSetAcrossBeacons() {
        let mld = "AA:AA:AA:AA:AA:00"
        let beacon5 = beacon(
            "AA:AA:AA:AA:AA:01", channel: 1, rssi: -50,
            elements: [multiLinkElement(apMLD: mld, details: ["Link 1 BSSID: AA:AA:AA:AA:AA:02"])]
        )
        let beacon24 = beacon(
            "AA:AA:AA:AA:AA:02", channel: 36, rssi: -60,
            elements: [multiLinkElement(apMLD: mld, details: ["Link 0 BSSID: AA:AA:AA:AA:AA:01"])]
        )
        let groups = MLOGroupAssembler.assemble(beacons: [beacon5, beacon24])
        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        XCTAssertEqual(group.apMLD, mld)
        XCTAssertEqual(group.ssid, "Home")
        let link0 = group.links.first { $0.linkID == 0 }
        let link1 = group.links.first { $0.linkID == 1 }
        XCTAssertEqual(link0?.bssid, "AA:AA:AA:AA:AA:01")
        XCTAssertEqual(link0?.channel, 1)
        XCTAssertEqual(link0?.rssi, -50)
        XCTAssertEqual(link0?.seenInCapture, true)
        XCTAssertEqual(link1?.bssid, "AA:AA:AA:AA:AA:02")
        XCTAssertEqual(link1?.channel, 36)
        XCTAssertEqual(link1?.seenInCapture, true)
    }

    func testLinkMissingFromCaptureIsMarkedNotSeen() {
        let mld = "BB:BB:BB:BB:BB:00"
        let lone = beacon(
            "BB:BB:BB:BB:BB:01", channel: 6, rssi: -70,
            elements: [multiLinkElement(apMLD: mld, details: ["Link 1 BSSID: BB:BB:BB:BB:BB:02"])]
        )
        let groups = MLOGroupAssembler.assemble(beacons: [lone])
        XCTAssertEqual(groups.count, 1)
        let group = groups[0]
        let missing = group.links.first { $0.linkID == 1 }
        XCTAssertEqual(missing?.bssid, "BB:BB:BB:BB:BB:02")
        XCTAssertEqual(missing?.seenInCapture, false)
        XCTAssertNil(missing?.channel)
        let reporting = group.links.first { $0.bssid == "BB:BB:BB:BB:BB:01" }
        XCTAssertEqual(reporting?.seenInCapture, true)
        XCTAssertEqual(reporting?.channel, 6)
    }

    func testBeaconsWithoutMLDProduceNoGroups() {
        let plain = beacon("CC:CC:CC:CC:CC:01", channel: 11, rssi: -80, elements: [])
        XCTAssertTrue(MLOGroupAssembler.assemble(beacons: [plain]).isEmpty)
    }
}
