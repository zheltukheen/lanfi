import LanFiCore
import XCTest

/// G8: the capture parser reads a client's association request and keeps the
/// values for the client card. The frame is built by hand so the test does not
/// depend on a captured file.
final class ClientCapabilityCaptureTests: XCTestCase {
    private let client = "AA:00:00:00:00:07"
    private let ap = "00:11:22:33:44:01"

    private func writeMAC(_ mac: String, at offset: Int, into frame: inout Data) {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        XCTAssertEqual(bytes.count, 6)
        for (index, byte) in bytes.enumerated() {
            frame[offset + index] = byte
        }
    }

    private func element(_ id: UInt8, _ payload: [UInt8]) -> Data {
        Data([id, UInt8(payload.count)] + payload)
    }

    private func associationRequest() -> Data {
        // 24-byte management header + capability info + listen interval.
        var frame = Data(repeating: 0, count: 28)
        frame[0] = 0x00
        frame[1] = 0x00  // association request
        frame[24] = 0x11
        frame[25] = 0x04  // capability info: ESS + privacy

        var ht = [UInt8](repeating: 0, count: 26)
        ht[3] = 0x03  // RX MCS bits 0–1: one stream
        let ies =
            element(1, [0x82, 0x84, 0x8B, 0x96, 0x0C, 0x12, 0x18, 0x24])
            + element(45, ht)
            + element(191, [0, 0, 0, 0, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
            + element(255, [35, 0x1F, 0x00])
        return frame + ies
    }

    func testAssociationRequestProducesClientCapabilities() throws {
        var frame = associationRequest()
        writeMAC(ap, at: 4, into: &frame)
        writeMAC(client, at: 10, into: &frame)
        writeMAC(ap, at: 16, into: &frame)

        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let clients = PcapAnalyzer.clients(
            beacons: [
                CapturedBeacon(
                    id: ap, bssid: ap, ssid: "Office", channel: 36, rssi: -60,
                    security: "WPA3", isEHT: false, informationElements: [],
                    clientCount: 2, timestamp: timestamp, source: "pcap")
            ],
            packets: [(UInt32(105), frame, timestamp, nil)])

        let entry = try XCTUnwrap(clients.first { $0.mac == client })
        XCTAssertEqual(entry.firstSeen, timestamp)
        XCTAssertEqual(entry.lastSeen, timestamp)

        let capabilities = try XCTUnwrap(entry.capabilities)
        XCTAssertEqual(capabilities.source, .associationRequest)
        XCTAssertEqual(capabilities.phy, [.n, .ac, .ax])
        XCTAssertEqual(capabilities.generation, .ax)
        XCTAssertEqual(capabilities.streams, 1)
        XCTAssertEqual(capabilities.supportedRatesMbps.first, 1)
        XCTAssertEqual(capabilities.supportedRatesMbps.last, 18)
    }

    func testClientWithoutAssociationFramesFallsBackToTheBeacon() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
        let beaconCapabilities = ClientCapabilitySummary(
            phy: [.n, .ax], streams: 2, supportedRatesMbps: [6, 24, 54],
            source: .beacon)
        let beacon = CapturedBeacon(
            id: ap, bssid: ap, ssid: "Office", channel: 36, rssi: -60,
            security: "WPA3", isEHT: false, informationElements: [],
            clientCount: 2, timestamp: timestamp, source: "pcap",
            capabilities: beaconCapabilities)

        var data = Data(repeating: 0, count: 24)
        data[0] = 0x08
        data[1] = 0x01  // ToDS: address1 is the AP, address2 the client
        writeMAC(ap, at: 4, into: &data)
        writeMAC(client, at: 10, into: &data)
        writeMAC(ap, at: 16, into: &data)

        let clients = PcapAnalyzer.clients(
            beacons: [beacon], packets: [(UInt32(105), data, timestamp, nil)])
        let entry = try XCTUnwrap(clients.first { $0.mac == client })
        XCTAssertEqual(entry.capabilities?.source, .beacon)
        XCTAssertEqual(entry.capabilities?.generation, .ax)
    }
}
