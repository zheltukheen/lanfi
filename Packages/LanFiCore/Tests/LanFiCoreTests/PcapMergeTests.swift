import XCTest

@testable import LanFiCore

/// G3: several one-radio captures become one pcapng where every packet still
/// names the sensor that saw it.
final class PcapMergeTests: XCTestCase {
    private func pcap(
        linkType: UInt32 = 127, bigEndian: Bool = false, nanoseconds: Bool = false,
        packets: [(time: TimeInterval, bytes: [UInt8])]
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        // The magic itself tells the reader the byte order.
        appendU32(&bytes, nanoseconds ? 0xA1B23C4D : 0xA1B2C3D4, bigEndian: bigEndian)
        appendU16(&bytes, 2, bigEndian: bigEndian)
        appendU16(&bytes, 4, bigEndian: bigEndian)
        appendU32(&bytes, 0, bigEndian: bigEndian)  // thiszone
        appendU32(&bytes, 0, bigEndian: bigEndian)  // sigfigs
        appendU32(&bytes, 65_535, bigEndian: bigEndian)  // snaplen
        appendU32(&bytes, linkType, bigEndian: bigEndian)
        for packet in packets {
            let seconds = UInt32(packet.time)
            let fraction =
                (packet.time - Double(seconds)) * (nanoseconds ? 1_000_000_000 : 1_000_000)
            appendU32(&bytes, seconds, bigEndian: bigEndian)
            appendU32(&bytes, UInt32(fraction), bigEndian: bigEndian)
            appendU32(&bytes, UInt32(packet.bytes.count), bigEndian: bigEndian)
            appendU32(&bytes, UInt32(packet.bytes.count), bigEndian: bigEndian)
            bytes.append(contentsOf: packet.bytes)
        }
        return bytes
    }

    private func appendU16(_ bytes: inout [UInt8], _ value: UInt16, bigEndian: Bool = false) {
        if bigEndian {
            bytes.append(UInt8((value >> 8) & 0xFF))
            bytes.append(UInt8(value & 0xFF))
        } else {
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))
        }
    }

    private func appendU32(_ bytes: inout [UInt8], _ value: UInt32, bigEndian: Bool = false) {
        if bigEndian {
            for shift in stride(from: 24, through: 0, by: -8) {
                bytes.append(UInt8((value >> UInt32(shift)) & 0xFF))
            }
        } else {
            for shift in stride(from: 0, to: 32, by: 8) {
                bytes.append(UInt8((value >> UInt32(shift)) & 0xFF))
            }
        }
    }

    func testPcapRoundTrip() throws {
        let capture = try PcapFile.parse(
            pcap(packets: [(1_700_000_000.25, [1, 2, 3]), (1_700_000_001, [4, 5])]))

        XCTAssertEqual(capture.linkType, 127)
        XCTAssertEqual(capture.packets.count, 2)
        XCTAssertEqual(capture.packets[0].data, [1, 2, 3])
        XCTAssertEqual(capture.packets[0].timestamp, 1_700_000_000.25, accuracy: 0.000_001)
        XCTAssertEqual(capture.packets[1].data, [4, 5])
    }

    func testBigEndianAndNanosecondHeadersAreAccepted() throws {
        let bigEndian = try PcapFile.parse(
            pcap(bigEndian: true, packets: [(10.5, [9])]))
        XCTAssertEqual(bigEndian.linkType, 127)
        XCTAssertEqual(bigEndian.packets, [PcapPacket(timestamp: 10.5, data: [9])])

        let nanoseconds = try PcapFile.parse(
            pcap(nanoseconds: true, packets: [(20.125, [7])]))
        XCTAssertEqual(nanoseconds.packets.first?.timestamp ?? 0, 20.125, accuracy: 0.000_001)

        XCTAssertThrowsError(try PcapFile.parse(Array("not a pcap file at all!!".utf8)))
    }

    func testTruncatedCaptureIsRejected() {
        var bytes = pcap(packets: [(1, [1, 2, 3, 4])])
        bytes.removeLast(2)
        XCTAssertThrowsError(try PcapFile.parse(bytes)) { error in
            XCTAssertEqual(error as? PcapMergeError, .truncated)
        }
    }

    func testMergeOrdersPacketsAndKeepsTheSensorOfEach() throws {
        let first = CaptureSource(
            name: "wlan-pi-1", detail: "192.0.2.10",
            capture: try PcapFile.parse(
                pcap(packets: [(100.0, [1]), (102.0, [3])])))
        let second = CaptureSource(
            name: "wlan-pi-2", detail: "192.0.2.11",
            capture: try PcapFile.parse(
                pcap(packets: [(101.0, [2]), (103.0, [4])])))

        let merged = try PcapMerge.merge([first, second])

        XCTAssertEqual(merged.packetCount, 4)
        XCTAssertEqual(merged.packetSensors, ["wlan-pi-1", "wlan-pi-2", "wlan-pi-1", "wlan-pi-2"])
        XCTAssertEqual(merged.sensor(forPacketIndex: 1), "wlan-pi-2")
        XCTAssertNil(merged.sensor(forPacketIndex: 9))
        XCTAssertEqual(merged.interfaceIDs, ["wlan-pi-1": 0, "wlan-pi-2": 1])
        XCTAssertEqual(merged.sensorNames, ["wlan-pi-1", "wlan-pi-2"])
        XCTAssertEqual(Array(merged.pcapng.prefix(4)), [0x0A, 0x0D, 0x0D, 0x0A])
        // The sensor names are in the interface blocks, not only in the model.
        let text = String(decoding: merged.pcapng, as: UTF8.self)
        XCTAssertTrue(text.contains("wlan-pi-1"))
        XCTAssertTrue(text.contains("192.0.2.11"))
    }

    func testBlockLengthsAddUp() throws {
        let source = CaptureSource(
            name: "sensor", capture: try PcapFile.parse(pcap(packets: [(5, [1, 2, 3])])))
        let merged = try PcapMerge.merge([source])
        let bytes = merged.pcapng

        var offset = 0
        var types: [UInt32] = []
        while offset + 8 <= bytes.count {
            let type = PcapFile.readU32(bytes, offset, littleEndian: true)
            let length = Int(PcapFile.readU32(bytes, offset + 4, littleEndian: true))
            XCTAssertGreaterThanOrEqual(length, 12)
            XCTAssertLessThanOrEqual(offset + length, bytes.count)
            XCTAssertEqual(Int(PcapFile.readU32(bytes, offset + length - 4, littleEndian: true)), length)
            types.append(type)
            offset += length
        }
        XCTAssertEqual(offset, bytes.count)
        XCTAssertEqual(types, [0x0A0D0D0A, 1, 6])
    }

    func testEmptySensorListIsRejectedAndEmptyCaptureIsValid() throws {
        XCTAssertThrowsError(try PcapMerge.merge([])) { error in
            XCTAssertEqual(error as? PcapMergeError, .noSensors)
        }

        let empty = try PcapMerge.merge([
            CaptureSource(name: "quiet", capture: PcapCapture(linkType: 127, packets: []))
        ])
        XCTAssertEqual(empty.packetCount, 0)
        XCTAssertEqual(empty.interfaceIDs, ["quiet": 0])
        XCTAssertEqual(Array(empty.pcapng.prefix(4)), [0x0A, 0x0D, 0x0D, 0x0A])
    }
}
