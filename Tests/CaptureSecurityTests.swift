import XCTest

final class PcapSecurityTests: XCTestCase {
    func testCompleteHandshakeAndPMKIDAreDetected() throws {
        let network = makeNetwork(bssid: "AA:BB:CC:DD:EE:01", ssid: "Home", channel: 6)
        let client = "3C:22:FB:11:22:33"
        let keyData = pmkidKeyData()
        let data = pcapCapture(
            frames: [
                try XCTUnwrap(PcapExporter.beaconFrame(for: network)),
                eapolFrame(client: client, bssid: network.bssid, message: 1, keyData: keyData),
                eapolFrame(client: client, bssid: network.bssid, message: 2),
                deauthFrame(client: client, bssid: network.bssid, reason: 2),
            ])

        let summary = try PcapAnalyzer.summary(data: data)
        let handshake = try XCTUnwrap(summary.security.handshake(for: network.bssid))
        XCTAssertEqual(handshake.messages, [1, 2])
        XCTAssertTrue(handshake.hasCompleteHandshake)
        XCTAssertTrue(handshake.hasPMKID)
        XCTAssertEqual(handshake.keyFrameCount, 2)

        let counters = try XCTUnwrap(summary.security.counters(for: network.bssid))
        XCTAssertEqual(counters.deauth, 1)
        XCTAssertEqual(counters.reasons.first?.code, 2)

        XCTAssertEqual(summary.security.pmkidCount, 1)
        XCTAssertEqual(summary.security.completeHandshakeCount, 1)
        XCTAssertTrue(summary.security.findings.contains { $0.id.hasPrefix("pmkid-") })
        XCTAssertTrue(summary.security.findings.contains { $0.id.hasPrefix("handshake-") })
    }

    func testPartialHandshakeIsNotReportedAsComplete() throws {
        let network = makeNetwork(bssid: "AA:BB:CC:DD:EE:02", ssid: "Partial", channel: 1)
        let data = pcapCapture(frames: [
            try XCTUnwrap(PcapExporter.beaconFrame(for: network)),
            eapolFrame(client: "3C:22:FB:11:22:44", bssid: network.bssid, message: 1),
        ])
        let summary = try PcapAnalyzer.summary(data: data)
        let handshake = try XCTUnwrap(summary.security.handshake(for: network.bssid))
        XCTAssertEqual(handshake.messages, [1])
        XCTAssertFalse(handshake.hasCompleteHandshake)
        XCTAssertEqual(summary.security.completeHandshakeCount, 0)
    }

    func testClientsCaptureVendorSignalsAndProbeSSIDs() throws {
        let network = makeNetwork(bssid: "AA:BB:CC:DD:EE:03", ssid: "Home", channel: 11)
        let client = "00:1B:63:11:22:33"
        let data = pcapCapture(frames: [
            try XCTUnwrap(PcapExporter.beaconFrame(for: network)),
            probeRequestFrame(client: client, ssid: "Home"),
            eapolFrame(client: client, bssid: network.bssid, message: 2),
        ])
        let clients = try PcapAnalyzer.clients(data: data)
        let entry = try XCTUnwrap(clients.first { $0.mac == client })
        XCTAssertEqual(entry.probeSSIDs, ["Home"])
        XCTAssertEqual(entry.eapolFrames, 1)
        XCTAssertEqual(entry.bssid, network.bssid)
        XCTAssertNotEqual(entry.lastSeen, .distantPast)
        XCTAssertGreaterThan(entry.frameCount, 1)
    }
}

final class CaptureSecurityAnalyzerTests: XCTestCase {
    func testOfflineCrackableFollowsAdvertisedSecurity() {
        XCTAssertTrue(CaptureSecurityAnalyzer.isOfflineCrackable(security: "WPA2 Personal", pmkid: false))
        XCTAssertTrue(
            CaptureSecurityAnalyzer.isOfflineCrackable(security: "WPA3 Transition", pmkid: false))
        XCTAssertFalse(CaptureSecurityAnalyzer.isOfflineCrackable(security: "WPA3 Personal", pmkid: false))
        XCTAssertFalse(
            CaptureSecurityAnalyzer.isOfflineCrackable(security: "WPA2 Enterprise", pmkid: false))
        XCTAssertFalse(CaptureSecurityAnalyzer.isOfflineCrackable(security: "Open", pmkid: false))
        XCTAssertTrue(CaptureSecurityAnalyzer.isOfflineCrackable(security: nil, pmkid: true))
    }

    func testBurstNeedsEnoughFramesInsideTheWindow() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let tight = (0..<CaptureSecurityAnalyzer.burstThreshold).map {
            base.addingTimeInterval(Double($0) * 0.2)
        }
        XCTAssertTrue(CaptureSecurityAnalyzer.burstDetected(times: tight))

        let spread = (0..<CaptureSecurityAnalyzer.burstThreshold).map {
            base.addingTimeInterval(Double($0) * 4)
        }
        XCTAssertFalse(CaptureSecurityAnalyzer.burstDetected(times: spread))
        XCTAssertFalse(CaptureSecurityAnalyzer.burstDetected(times: Array(tight.prefix(3))))
    }

    func testBurstProducesCriticalFinding() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let times = (0..<10).map { base.addingTimeInterval(Double($0) * 0.3) }
        let counters = [ManagementCounters(bssid: "AA:BB:CC:DD:EE:04", deauth: 10)]
        let report = CaptureSecurityAnalyzer.report(
            handshakes: [], counters: counters, beacons: [],
            deauthTimes: ["AA:BB:CC:DD:EE:04": times])

        XCTAssertTrue(try XCTUnwrap(report.counters(for: "AA:BB:CC:DD:EE:04")).burst)
        XCTAssertEqual(report.findings.first?.severity, .critical)
    }

    func testBeaconFloodNeedsRandomizedBSSIDs() {
        let randomized = (0..<6).map { index in
            beacon(bssid: String(format: "02:00:00:00:00:%02X", index), ssid: "Free WiFi")
        }
        XCTAssertEqual(CaptureSecurityAnalyzer.beaconFloodCandidates(beacons: randomized).first?.1, 6)

        let registered = (0..<6).map { index in
            beacon(bssid: String(format: "00:1A:2B:00:00:%02X", index), ssid: "Free WiFi")
        }
        XCTAssertTrue(CaptureSecurityAnalyzer.beaconFloodCandidates(beacons: registered).isEmpty)
    }
}

final class CaptureProfileTests: XCTestCase {
    func testParseChannelsDropsJunkAndDuplicates() {
        XCTAssertEqual(CaptureProfile.parseChannels("1, 6,11"), [1, 6, 11])
        XCTAssertEqual(CaptureProfile.parseChannels("6;6;36"), [6, 36])
        XCTAssertEqual(CaptureProfile.parseChannels("0, 300, abc"), [])
    }

    func testSingleChannelIsPinned() {
        let single = CaptureProfile.new(
            name: "pinned", interfaceName: "en0", duration: 10, monitorMode: true, filter: "",
            channels: [6])
        XCTAssertEqual(single.pinnedChannel, 6)

        let multi = CaptureProfile.new(
            name: "plan", interfaceName: "en0", duration: 10, monitorMode: true, filter: "",
            channels: [1, 6, 11])
        XCTAssertNil(multi.pinnedChannel)
        XCTAssertEqual(multi.channelListLabel, "1,6,11")
    }

    func testOldProfilesWithoutChannelsStillDecode() throws {
        let json = """
            {"id":"\(UUID().uuidString)","name":"legacy","interfaceName":"en0","duration":20,\
            "monitorMode":true,"filter":"","channel":44}
            """
        let profile = try JSONDecoder().decode(CaptureProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.channel, 44)
        XCTAssertNil(profile.channels)
        XCTAssertEqual(profile.pinnedChannel, 44)
    }
}

// MARK: - Frame fixtures

private func pcapCapture(frames: [Data], linkType: UInt32 = 127) -> Data {
    var data = Data()
    data.append(contentsOf: [0xD4, 0xC3, 0xB2, 0xA1])  // little-endian magic
    data.append(contentsOf: [0x02, 0x00, 0x04, 0x00])
    data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])  // thiszone, sigfigs
    data.append(contentsOf: [0xFF, 0xFF, 0x00, 0x00])  // snaplen
    data.append(contentsOf: linkType.littleEndianBytes)

    for (index, frame) in frames.enumerated() {
        var packet = Data([0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])  // radiotap
        packet.append(frame)
        data.append(contentsOf: UInt32(1_700_000_000 + index).littleEndianBytes)
        data.append(contentsOf: UInt32(0).littleEndianBytes)
        data.append(contentsOf: UInt32(packet.count).littleEndianBytes)
        data.append(contentsOf: UInt32(packet.count).littleEndianBytes)
        data.append(packet)
    }
    return data
}

private func macBytes(_ value: String) -> Data {
    Data(
        value.split(separator: ":").compactMap { UInt8($0, radix: 16) })
}

private func header(fc: UInt16, address1: String, address2: String, address3: String) -> Data {
    var frame = Data()
    frame.append(contentsOf: fc.littleEndianBytes)
    frame.append(contentsOf: [0x00, 0x00])
    frame.append(macBytes(address1))
    frame.append(macBytes(address2))
    frame.append(macBytes(address3))
    frame.append(contentsOf: [0x00, 0x00])
    return frame
}

private func probeRequestFrame(client: String, ssid: String) -> Data {
    var frame = header(
        fc: 0x0040, address1: "FF:FF:FF:FF:FF:FF", address2: client,
        address3: "FF:FF:FF:FF:FF:FF")
    let ssidBytes = Data(ssid.utf8)
    frame.append(contentsOf: [0x00, UInt8(ssidBytes.count)])
    frame.append(ssidBytes)
    frame.append(contentsOf: [0x01, 0x01, 0x82])  // supported rates
    return frame
}

private func deauthFrame(client: String, bssid: String, reason: UInt16) -> Data {
    var frame = header(fc: 0x00C0, address1: client, address2: bssid, address3: bssid)
    frame.append(contentsOf: reason.littleEndianBytes)
    return frame
}

private func pmkidKeyData() -> Data {
    var data = Data([0xDD, 0x14, 0x00, 0x0F, 0xAC, 0x04])
    data.append(contentsOf: [UInt8](repeating: 0xAB, count: 16))
    return data
}

/// Builds a data frame carrying an EAPOL-Key message the way a client or AP
/// would send it. `keyData` is only used for message 1.
private func eapolFrame(client: String, bssid: String, message: Int, keyData: Data = Data()) -> Data {
    var frame = header(fc: 0x0108, address1: bssid, address2: client, address3: bssid)
    frame.append(contentsOf: [0xAA, 0xAA, 0x03, 0x00, 0x00, 0x00, 0x88, 0x8E])

    let keyInfo: UInt16
    switch message {
    case 1: keyInfo = 0x0082  // ACK
    case 2: keyInfo = 0x0102  // MIC
    case 3: keyInfo = 0x01C2  // ACK | MIC | Install
    default: keyInfo = 0x0302  // MIC | Secure
    }

    var body = Data([0x02, 0x03])  // EAPOL version 2, type Key
    body.append(contentsOf: UInt16(95 + keyData.count).bigEndianBytes)
    body.append(0x02)  // RSN key descriptor
    body.append(contentsOf: keyInfo.bigEndianBytes)
    body.append(contentsOf: [0x00, 0x00])  // key length
    body.append(contentsOf: [UInt8](repeating: 0, count: 8))  // replay counter
    body.append(contentsOf: [UInt8](repeating: 0x11, count: 32))  // nonce
    body.append(contentsOf: [UInt8](repeating: 0, count: 16))  // IV
    body.append(contentsOf: [UInt8](repeating: 0, count: 8))  // RSC
    body.append(contentsOf: [UInt8](repeating: 0, count: 8))  // key ID
    body.append(contentsOf: [UInt8](repeating: 0, count: 16))  // MIC
    body.append(contentsOf: UInt16(keyData.count).bigEndianBytes)
    body.append(keyData)
    frame.append(body)
    return frame
}

private func beacon(bssid: String, ssid: String) -> CapturedBeacon {
    CapturedBeacon(
        id: "\(bssid)-\(ssid)", bssid: bssid, ssid: ssid, channel: 6, rssi: -50,
        security: "Open", isEHT: false, informationElements: [], clientCount: nil,
        timestamp: Date(), source: "test"
    )
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }

    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: bigEndian) { Array($0) }
    }
}
