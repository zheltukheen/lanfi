import LanFiCore
import XCTest

/// G3: an offline capture merged from two sensors must say which radio saw a
/// beacon, a client and a deauth frame.
final class CaptureSensorAttributionTests: XCTestCase {
    private let bssid = "AA:BB:CC:DD:EE:10"
    private let client = "AA:BB:CC:DD:EE:20"

    // MARK: - Frame builders (bare 802.11, link type 105)

    private func mac(_ text: String) -> [UInt8] {
        text.split(separator: ":").compactMap { UInt8($0, radix: 16) }
    }

    private func header(_ frameControl: UInt16, _ addresses: [String]) -> [UInt8] {
        var bytes: [UInt8] = [
            UInt8(frameControl & 0xFF), UInt8(frameControl >> 8),
            0x00, 0x00,
        ]
        for address in addresses { bytes.append(contentsOf: mac(address)) }
        bytes.append(contentsOf: [0x00, 0x00])  // sequence control
        return bytes
    }

    private func beacon(ssid: String) -> [UInt8] {
        var bytes = header(0x0080, ["FF:FF:FF:FF:FF:FF", bssid, bssid])
        bytes.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])  // timestamp
        bytes.append(contentsOf: [0x64, 0x00])  // beacon interval
        bytes.append(contentsOf: [0x01, 0x04])  // capability
        let name = Array(ssid.utf8)
        bytes.append(contentsOf: [0, UInt8(name.count)])
        bytes.append(contentsOf: name)
        bytes.append(contentsOf: [3, 1, 36])  // DS parameter, channel 36
        return bytes
    }

    private func deauth() -> [UInt8] {
        var bytes = header(0x00C0, [client, bssid, bssid])
        bytes.append(contentsOf: [2, 0])  // reason: previous auth invalid
        return bytes
    }

    private func dataFrame() -> [UInt8] {
        var bytes = header(0x0008, [bssid, client, bssid])
        bytes.append(contentsOf: [0xAA, 0xAA, 0x03, 0x00, 0x00, 0x00, 0x08, 0x00])
        return bytes
    }

    private func pcap(_ frames: [[UInt8]]) -> PcapCapture {
        var packets: [PcapPacket] = []
        for (index, frame) in frames.enumerated() {
            packets.append(
                PcapPacket(timestamp: 1_700_000_000 + Double(index), data: frame))
        }
        return PcapCapture(linkType: 105, packets: packets)
    }

    private func mergedCapture() throws -> Data {
        let frames: [[UInt8]] = [beacon(ssid: "LanFi Lab"), deauth(), dataFrame()]
        let merged = try PcapMerge.merge([
            CaptureSource(name: "left", capture: pcap(frames)),
            CaptureSource(name: "right", capture: pcap(frames)),
        ])
        return Data(merged.pcapng)
    }

    func testBeaconsNameEverySensorThatHeardThem() throws {
        let summary = try PcapAnalyzer.summary(data: mergedCapture())
        let beacon = try XCTUnwrap(summary.beacons.first)
        XCTAssertEqual(beacon.ssid, "LanFi Lab")
        XCTAssertEqual(beacon.sensors.sorted(), ["left", "right"])
        XCTAssertEqual(summary.sensorNames, ["left", "right"])
    }

    func testClientKeepsTheSensorsThatSawItsFrames() throws {
        let summary = try PcapAnalyzer.summary(data: mergedCapture())
        let entry = try XCTUnwrap(summary.clients.first { $0.mac == client })
        XCTAssertEqual(entry.sensorNames, ["left", "right"])
        XCTAssertGreaterThan(entry.frameCount, 0)
    }

    func testDeauthIsAttributedToItsSensors() throws {
        let summary = try PcapAnalyzer.summary(data: mergedCapture())
        let counters = try XCTUnwrap(summary.security.counters(for: bssid))
        XCTAssertEqual(counters.deauth, 2)
        XCTAssertEqual(counters.deauthSensorNames, ["left", "right"])
        XCTAssertEqual(counters.sensorNames, ["left", "right"])
        XCTAssertEqual(summary.security.deauthSensorNames, ["left", "right"])
        let finding = try XCTUnwrap(
            summary.security.findings.first { $0.id == "deauth-\(bssid)" })
        XCTAssertTrue(finding.detail.contains("left"), finding.detail)
        XCTAssertTrue(finding.detail.contains("right"), finding.detail)
    }

    func testSingleSensorCaptureHasNoAttribution() throws {
        let merged = try PcapMerge.merge([
            CaptureSource(name: "solo", capture: pcap([beacon(ssid: "Solo"), deauth()]))
        ])
        let summary = try PcapAnalyzer.summary(data: Data(merged.pcapng))
        XCTAssertEqual(summary.beacons.first?.sensors, ["solo"])
        XCTAssertEqual(summary.security.counters(for: bssid)?.deauthSensorNames, ["solo"])
    }
}
