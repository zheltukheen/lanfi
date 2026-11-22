import Foundation
import XCTest

final class NativePingTests: XCTestCase {
    func testChecksumOfAValidRequestVerifiesToZero() {
        let packet = ICMPEcho.request(identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4])
        XCTAssertEqual(packet.count, 12)
        XCTAssertEqual(packet[0], 8)
        XCTAssertEqual(ICMPEcho.checksum(packet), 0)
    }

    func testRequestCarriesIdentifierAndSequence() {
        let packet = ICMPEcho.request(identifier: 0xBEEF, sequence: 0x0102, payload: [])
        XCTAssertEqual(Array(packet[4...7]), [0xBE, 0xEF, 0x01, 0x02])
    }

    func testReplyParsingIgnoresRequestsAndShortDatagrams() {
        var reply = [UInt8](repeating: 0, count: 8)
        reply[0] = 0
        reply[4] = 0x12
        reply[5] = 0x34
        reply[6] = 0x00
        reply[7] = 0x09
        XCTAssertEqual(
            ICMPEcho.parseReply(reply),
            ICMPEcho.Reply(type: 0, identifier: 0x1234, sequence: 9))
        reply[0] = 8
        XCTAssertNil(ICMPEcho.parseReply(reply))
        XCTAssertNil(ICMPEcho.parseReply([0, 0, 0]))
    }

    func testStatisticsReportLossAndSpread() {
        let result = ICMPEcho.statistics(sent: 4, roundTrips: [10, 20, 30])
        XCTAssertEqual(result?.received, 3)
        XCTAssertEqual(result?.packetLossPercent, 25)
        XCTAssertEqual(result?.minMilliseconds, 10)
        XCTAssertEqual(result?.maxMilliseconds, 30)
        XCTAssertEqual(result?.averageMilliseconds, 20)
        XCTAssertEqual(result?.standardDeviationMilliseconds ?? 0, sqrt(200.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(ICMPEcho.statistics(sent: 0, roundTrips: []), nil)
    }

    func testUnresolvableHostDoesNotHang() {
        XCTAssertNil(
            NativePing.run(
                host: "this-host-does-not-exist.invalid", count: 1,
                timeoutMilliseconds: 100, payloadSize: 8))
    }
}

final class LiveThreatCounterTests: XCTestCase {
    func testSnapshotMapsReportCounters() {
        var report = CaptureSecurityReport.empty
        report.management = [
            ManagementCounters(
                bssid: "AA:BB:CC:DD:EE:FF", beacons: 5, probeResponses: 2,
                deauth: 3, disassoc: 1, burst: true)
        ]
        report.handshakes = [
            EAPOLHandshake(
                bssid: "AA:BB:CC:DD:EE:FF", keyFrameCount: 4, messages: [1, 2],
                hasPMKID: true, firstSeen: Date(), lastSeen: Date())
        ]
        let snapshot = LiveThreatSnapshot.make(report: report, bytes: 4096)
        XCTAssertEqual(snapshot.deauth, 3)
        XCTAssertEqual(snapshot.disassoc, 1)
        XCTAssertEqual(snapshot.eapolKeyFrames, 4)
        XCTAssertEqual(snapshot.completeHandshakes, 1)
        XCTAssertEqual(snapshot.pmkids, 1)
        XCTAssertEqual(snapshot.bursts, 1)
        XCTAssertEqual(snapshot.disruptionTotal, 4)
        XCTAssertEqual(LiveThreatSnapshot.empty.isEmpty, true)
    }
}

final class BLEBeaconParserTests: XCTestCase {
    func testAppleIBeaconManufacturerData() {
        var bytes: [UInt8] = [0x4C, 0x00, 0x02, 0x15]
        bytes.append(contentsOf: Array(repeating: 0x11, count: 16))
        bytes.append(contentsOf: [0x00, 0x0A, 0x00, 0x64, 0xC5])
        let beacon = BLEBeaconParser.iBeacon(
            manufacturerData: Data(bytes), name: "Lobby", rssi: -61, id: "A")
        XCTAssertEqual(beacon?.kind, .iBeacon)
        XCTAssertEqual(beacon?.major, 10)
        XCTAssertEqual(beacon?.minor, 100)
        XCTAssertEqual(beacon?.txPower, -59)
        XCTAssertTrue(beacon?.detail.contains("11111111") == true)
    }

    func testOtherManufacturerDataIsIgnored() {
        XCTAssertNil(
            BLEBeaconParser.iBeacon(
                manufacturerData: Data([0x4C, 0x00, 0x10, 0x05, 1, 2, 3]),
                name: "", rssi: -50, id: "A"))
    }

    func testEddystoneURLDecoding() {
        let data = Data([0x10, 0xEC, 0x03] + Array("example.com".utf8))
        let beacon = BLEBeaconParser.eddystone(
            serviceData: data, name: "", rssi: -70, id: "B")
        XCTAssertEqual(beacon?.kind, .eddystoneURL)
        XCTAssertEqual(beacon?.url, "https://example.com")
        XCTAssertEqual(beacon?.txPower, -20)
    }

    func testEddystoneUIDAndTLM() {
        let uid = Data([0x00, 0xEE] + Array(repeating: 0xAB, count: 10) + Array(repeating: 0xCD, count: 6))
        let uidBeacon = BLEBeaconParser.eddystone(serviceData: uid, name: "", rssi: -80, id: "C")
        XCTAssertEqual(uidBeacon?.kind, .eddystoneUID)
        XCTAssertEqual(uidBeacon?.namespaceID, String(repeating: "AB", count: 10))
        XCTAssertEqual(uidBeacon?.instanceID, String(repeating: "CD", count: 6))

        let tlm = Data([0x20, 0x00, 0x0F, 0xA0, 0x00, 0x15, 0, 0, 0, 1, 0, 0, 0, 2])
        let tlmBeacon = BLEBeaconParser.eddystone(serviceData: tlm, name: "", rssi: -80, id: "D")
        XCTAssertEqual(tlmBeacon?.kind, .eddystoneTLM)
        XCTAssertTrue(tlmBeacon?.detail.contains("4.000 V") == true)
    }

    func testZigbeeOverlapAndQuietChannels() {
        XCTAssertEqual(ZigbeeCoexistence.frequencyMHz(channel: 11), 2405)
        XCTAssertEqual(ZigbeeCoexistence.frequencyMHz(channel: 26), 2480)
        XCTAssertNil(ZigbeeCoexistence.frequencyMHz(channel: 10))
        XCTAssertTrue(
            ZigbeeCoexistence.overlappingWiFiChannels(zigbeeChannel: 15).contains(6))
        XCTAssertTrue(ZigbeeCoexistence.quietChannels.contains(20))
        XCTAssertFalse(ZigbeeCoexistence.quietChannels.contains(11))
    }
}

final class SpectrumInterferenceTests: XCTestCase {
    private func sweep(amplitudes: [Double], start: Double = 2400, step: Double = 1) -> SpectrumSweep {
        SpectrumSweep(
            source: "test", capturedAt: Date(), startMHz: start, stepMHz: step,
            amplitudes: amplitudes)
    }

    func testWideLobeIsClassifiedAsWifiOrMicrowave() {
        var values = [Double](repeating: -100, count: 100)
        for index in 30..<66 { values[index] = -55 }
        let interferers = SpectrumClassifier.classify(sweep(amplitudes: values))
        XCTAssertFalse(interferers.isEmpty)
        XCTAssertTrue([.wifi, .microwave].contains(interferers[0].kind))
        XCTAssertEqual(interferers[0].levelDBM, -55)
    }

    func testNarrowPeakIn2GHzIsNarrowband() {
        var values = [Double](repeating: -100, count: 100)
        values[40] = -60
        let interferers = SpectrumClassifier.classify(sweep(amplitudes: values))
        XCTAssertEqual(interferers.first?.kind, .narrowband24)
    }

    func testFlatSweepHasNoInterferers() {
        XCTAssertTrue(
            SpectrumClassifier.classify(sweep(amplitudes: [Double](repeating: -95, count: 50)))
                .isEmpty)
    }

    func testRemoteJSONSweepParsing() {
        let data = Data(
            #"{"startMHz":2400,"stepMHz":0.5,"amplitudes":[-90,-80,-70]}"#.utf8)
        let parsed = RemoteSpectrumSource.parseJSON(data, source: "wlanpi")
        XCTAssertEqual(parsed?.startMHz, 2400)
        XCTAssertEqual(parsed?.stepMHz, 0.5)
        XCTAssertEqual(parsed?.pointCount, 3)
        XCTAssertNil(RemoteSpectrumSource.parseJSON(Data("nope".utf8), source: "x"))
    }
}

final class ProtocolDecoderVersionTests: XCTestCase {
    func testDecoderVersionIsStamped() {
        XCTAssertEqual(ProtocolDecoderVersion.current.standard, "802.11bn")
        XCTAssertTrue(ProtocolDecoderVersion.current.shortLabel.contains("decoder"))
        XCTAssertNotNil(ProtocolDecoderVersion.note(for: .mode11be))
        XCTAssertNil(ProtocolDecoderVersion.note(for: .mode11ax))
    }
}
