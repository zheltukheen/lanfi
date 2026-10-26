import XCTest

final class PcapExporterTests: XCTestCase {
    func testCaptureHeaderAndLinkType() {
        let network = makeNetwork(ssid: "Capture Fixture", band: .band5, channel: 36)
        let data = PcapExporter.makeCapture(networks: [network])
        XCTAssertGreaterThan(data.count, 24)

        let magic = data.prefix(4).reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        XCTAssertEqual(magic, 0xA1B2C3D4)

        let linkType = data[20..<24].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        XCTAssertEqual(linkType, PcapExporter.linkTypeIEEE80211Radiotap)
    }

    func testOneBeaconPerNetworkAndSsidPresent() throws {
        let networks = [
            makeNetwork(id: "a", ssid: "Alpha", band: .band24, channel: 1),
            makeNetwork(id: "b", ssid: "Beta", band: .band5, channel: 36),
        ]
        let data = PcapExporter.makeCapture(networks: networks)
        XCTAssertTrue(data.range(of: Data("Alpha".utf8)) != nil)
        XCTAssertTrue(data.range(of: Data("Beta".utf8)) != nil)

        // 24-byte global header + two (16-byte packet header + packet).
        var offset = 24
        var packets = 0
        while offset + 16 <= data.count {
            let length = data[offset + 8..<offset + 12].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            offset += 16 + Int(length)
            packets += 1
        }
        XCTAssertEqual(packets, 2)
        XCTAssertEqual(offset, data.count)
    }

    func testEmptyBSSIDStillProducesBeacon() throws {
        let network = makeNetwork(bssid: "", ssid: "Hidden", channel: 6)
        let frame = try XCTUnwrap(PcapExporter.beaconFrame(for: network))
        XCTAssertGreaterThan(frame.count, 36)
    }

    func testUnicastMacIsConvertedToSixBytes() throws {
        let frame = try XCTUnwrap(PcapExporter.beaconFrame(for: makeNetwork(bssid: "00:1A:2B:3C:4D:5E")))
        XCTAssertTrue(frame.range(of: Data([0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E])) != nil)
    }
}

final class PcapAnalyzerTests: XCTestCase {
    func testParsesClassicPcapBeacon() throws {
        let network = makeNetwork(
            bssid: "00:11:22:33:44:55", ssid: "Offline", band: .band5, channel: 36
        )
        let data = PcapExporter.makeCapture(networks: [network])
        let beacons = try PcapAnalyzer.parse(data: data)
        let beacon = try XCTUnwrap(beacons.first)
        XCTAssertEqual(beacon.ssid, "Offline")
        XCTAssertEqual(beacon.bssid, "00:11:22:33:44:55")
        XCTAssertEqual(beacon.channel, 36)
        XCTAssertEqual(beacon.source, "pcap")
        XCTAssertFalse(beacon.informationElements.isEmpty)
    }

    func testParsesPcapngBeacon() throws {
        let network = makeNetwork(
            bssid: "AA:BB:CC:DD:EE:FF", ssid: "Pcapng", band: .band24, channel: 6
        )
        let data = PcapExporter.makePcapngCapture(networks: [network])
        XCTAssertEqual(data.prefix(4), Data([0x0A, 0x0D, 0x0D, 0x0A]))
        let beacons = try PcapAnalyzer.parse(data: data)
        let beacon = try XCTUnwrap(beacons.first)
        XCTAssertEqual(beacon.ssid, "Pcapng")
        XCTAssertEqual(beacon.bssid, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(beacon.channel, 6)
        XCTAssertEqual(beacon.source, "pcapng")
    }

    func testRejectsUnknownCapture() {
        XCTAssertThrowsError(try PcapAnalyzer.parse(data: Data("not a capture".utf8)))
    }
}

final class PcapLinkTypeTests: XCTestCase {
    func testRejectsRawIPCaptureForWiFiAnalysis() {
        var data = PcapExporter.makeCapture(networks: [makeNetwork(ssid: "X", channel: 36)])
        // Classic pcap link type field is at byte 20.
        data[20] = 101
        data[21] = 0
        data[22] = 0
        data[23] = 0
        XCTAssertThrowsError(try PcapAnalyzer.parse(data: data)) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("raw IP") || error.localizedDescription.contains("802.11"))
        }
    }
}
