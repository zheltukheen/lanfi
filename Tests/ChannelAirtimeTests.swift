import XCTest

/// G7 — per-BSSID airtime from a capture and the 802.11b legacy detector.
final class ChannelAirtimeTests: XCTestCase {
    private func writeMAC(_ mac: String, at offset: Int, into frame: inout Data) {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        XCTAssertEqual(bytes.count, 6)
        for (index, byte) in bytes.enumerated() {
            frame[offset + index] = byte
        }
    }

    /// FromDS data frame: address1 is the client, address2 the AP.
    private func apFrame(client: String, ap: String, duration: Int) -> Data {
        var frame = Data(repeating: 0, count: 24)
        frame[0] = 0x08
        frame[1] = 0x02  // FromDS
        frame[2] = UInt8(duration & 0xFF)
        frame[3] = UInt8((duration >> 8) & 0xFF)
        writeMAC(client, at: 4, into: &frame)
        writeMAC(ap, at: 10, into: &frame)
        return frame
    }

    private func radiotap(rateMbps: Double) -> Data {
        var header = Data([0, 0, 9, 0, 0x04, 0, 0, 0, 0])
        // Radiotap Rate: 500 kbit/s units.
        header[8] = UInt8((rateMbps / 0.5).rounded())
        return header
    }

    private func beacon(_ bssid: String, ssid: String) -> CapturedBeacon {
        CapturedBeacon(
            id: bssid, bssid: bssid, ssid: ssid, channel: 36, rssi: -55,
            security: "WPA3", isEHT: false, informationElements: [], clientCount: 3,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000), source: "pcap")
    }

    func testAirtimeIsAttributedToTheTransmittingBSSID() throws {
        let apA = "00:11:22:33:44:01"
        let apB = "00:11:22:33:44:02"
        let packets: [(UInt32, Data, Date)] = [
            (105, apFrame(client: "AA:00:00:00:00:01", ap: apA, duration: 3000), Date()),
            (105, apFrame(client: "AA:00:00:00:00:01", ap: apA, duration: 1000), Date()),
            (105, apFrame(client: "AA:00:00:00:00:02", ap: apB, duration: 1000), Date()),
        ]
        let entries = PcapAnalyzer.channelAirtime(
            beacons: [beacon(apA, ssid: "Mine"), beacon(apB, ssid: "Neighbour")],
            packets: packets)

        XCTAssertEqual(entries.map(\.bssid), [apA, apB])
        XCTAssertEqual(entries[0].ssid, "Mine")
        XCTAssertEqual(entries[0].frames, 2)
        XCTAssertEqual(entries[0].airtimeMicroseconds, 4000)
        XCTAssertEqual(try XCTUnwrap(entries[0].share), 0.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(entries[1].share), 0.2, accuracy: 0.0001)
        XCTAssertFalse(entries.contains { $0.isLegacy })
    }

    func testLegacyDataRateIsCountedFromRadiotap() throws {
        let ap = "00:11:22:33:44:01"
        let slow = radiotap(rateMbps: 1) + apFrame(client: "AA:00:00:00:00:01", ap: ap, duration: 500)
        let fast = radiotap(rateMbps: 54) + apFrame(client: "AA:00:00:00:00:02", ap: ap, duration: 500)
        let packets: [(UInt32, Data, Date)] = [(127, slow, Date()), (127, fast, Date())]
        let entries = PcapAnalyzer.channelAirtime(
            beacons: [beacon(ap, ssid: "Legacy AP")], packets: packets)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].dataFrames, 2)
        XCTAssertEqual(entries[0].legacyFrames, 1)
        XCTAssertTrue(entries[0].isLegacy)
    }

    func testBSSIDWithoutFramesStillAppearsWithZeroShare() throws {
        let ap = "00:11:22:33:44:09"
        let packets: [(UInt32, Data, Date)] = []
        let entries = PcapAnalyzer.channelAirtime(
            beacons: [beacon(ap, ssid: "Quiet")], packets: packets)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].frames, 0)
        XCTAssertNil(entries[0].share)
    }

    func testOnlyLegacyBasicRatesFlagALegacyAP() {
        XCTAssertTrue(
            LegacyWiFiDetector.flag(makeNetwork(basicRates: [1, 2, 5.5, 11])))
        XCTAssertFalse(
            LegacyWiFiDetector.flag(makeNetwork(basicRates: [6, 12, 24])))
        XCTAssertFalse(
            LegacyWiFiDetector.flag(makeNetwork(basicRates: [1, 2, 5.5, 11, 6, 12, 24])),
            "mixed-mode beacons are normal")
        XCTAssertFalse(LegacyWiFiDetector.flag(makeNetwork(basicRates: [])))
        XCTAssertTrue(LegacyWiFiDetector.isLegacyRate(5.5))
        XCTAssertFalse(LegacyWiFiDetector.isLegacyRate(12))
    }

    func testLegacySummaryNamesTheNetworkAndRates() throws {
        let network = makeNetwork(ssid: "Printer", basicRates: [1, 2, 5.5, 11])
        let summary = try XCTUnwrap(LegacyWiFiDetector.summary(for: network))
        XCTAssertTrue(summary.contains("Printer"))
        XCTAssertTrue(summary.contains("802.11b"))
    }

    func testChannelAirtimeFeedsAClientAnalyticsInsight() {
        let entries = [
            ChannelAirtimeEntry(
                bssid: "00:11:22:33:44:01", ssid: "Mine", frames: 10,
                airtimeMicroseconds: 7_000, dataFrames: 10, legacyFrames: 2, share: 0.7),
            ChannelAirtimeEntry(
                bssid: "00:11:22:33:44:02", ssid: "Neighbour", frames: 10,
                airtimeMicroseconds: 3_000, dataFrames: 10, legacyFrames: 0, share: 0.3),
        ]
        let snapshot = ClientAnalyticsSnapshot.build(
            networks: [], observations: [], channelAirtime: entries)
        XCTAssertEqual(snapshot.channelAirtime.count, 2)
        XCTAssertTrue(snapshot.insights.contains { $0.contains("70%") && $0.contains("Mine") })
        XCTAssertTrue(snapshot.insights.contains { $0.contains("802.11b") })
    }
}
