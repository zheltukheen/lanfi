import LanFiCore
import XCTest

final class PcapPacketIndexTests: XCTestCase {
    func testIndexesClassicPcapWithoutCopyingPackets() throws {
        let data = makePcap(packet: Data([0x01, 0x02, 0x03, 0x04]))

        let index = try PcapPacketIndex(data: data)
        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries[0].linkType, 127)
        XCTAssertEqual(index.entries[0].length, 4)

        var packets: [(UInt32, Data, Date, String?)] = []
        for packet in index {
            packets.append(packet)
        }
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0].0, 127)
        XCTAssertEqual(packets[0].1, Data([0x01, 0x02, 0x03, 0x04]))
        XCTAssertEqual(packets[0].2.timeIntervalSince1970, 1, accuracy: 0.001)
        XCTAssertNil(packets[0].3, "classic pcap has no interface names")
    }

    /// G3: a merged file names its interfaces; the index must carry that name
    /// with every packet so the analyzer can attribute frames to a sensor.
    func testMergedPcapngPacketsCarryTheirSensorName() throws {
        let merged = try PcapMerge.merge([
            CaptureSource(
                name: "wlan-pi-1",
                capture: PcapCapture(
                    linkType: 105,
                    packets: [PcapPacket(timestamp: 10, data: [1, 2, 3])])),
            CaptureSource(
                name: "wlan-pi-2",
                capture: PcapCapture(
                    linkType: 105,
                    packets: [PcapPacket(timestamp: 11, data: [4, 5, 6])])),
        ])

        let sensors = try PcapPacketIndex(data: Data(merged.pcapng)).map(\.3)
        XCTAssertEqual(sensors, ["wlan-pi-1", "wlan-pi-2"])
    }

    func testTruncatedPacketIsSkippedByIterator() throws {
        var data = makePcap(packet: Data([0x01]))
        data.removeLast()

        let index = try PcapPacketIndex(data: data)
        XCTAssertEqual(index.entries.count, 0)
        XCTAssertEqual(Array(index).count, 0)
    }

    private func makePcap(packet: Data) -> Data {
        var data = Data()
        data.appendLE(UInt32(0xA1B2C3D4))
        data.appendLE(UInt16(2))
        data.appendLE(UInt16(4))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(65_535))
        data.appendLE(UInt32(127))
        data.appendLE(UInt32(1))
        data.appendLE(UInt32(0))
        data.appendLE(UInt32(packet.count))
        data.appendLE(UInt32(packet.count))
        data.append(packet)
        return data
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
