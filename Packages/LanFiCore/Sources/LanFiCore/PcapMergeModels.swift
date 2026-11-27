import Foundation

public enum PcapMergeError: Error, Equatable, LocalizedError {
    case notPcap
    case truncated
    case noSensors

    public var errorDescription: String? {
        switch self {
        case .notPcap: return "The file is not a pcap capture."
        case .truncated: return "The capture ends in the middle of a packet."
        case .noSensors: return "There is no sensor capture to merge."
        }
    }
}

public struct PcapPacket: Equatable, Sendable {
    /// Seconds since 1970, from the record header.
    public let timestamp: TimeInterval
    public let data: [UInt8]
    public let originalLength: Int

    public init(timestamp: TimeInterval, data: [UInt8], originalLength: Int? = nil) {
        self.timestamp = timestamp
        self.data = data
        self.originalLength = originalLength ?? data.count
    }
}

public struct PcapCapture: Equatable, Sendable {
    public let linkType: UInt32
    public let packets: [PcapPacket]

    public init(linkType: UInt32, packets: [PcapPacket]) {
        self.linkType = linkType
        self.packets = packets
    }
}

/// Classic pcap reader. Only what a merge needs: the link type and the packet
/// records, in file order, both endiannesses and both timestamp resolutions.
public enum PcapFile {
    public static func parse(_ bytes: [UInt8]) throws -> PcapCapture {
        guard bytes.count >= 24 else { throw PcapMergeError.notPcap }
        let littleEndian: Bool
        let nanoseconds: Bool
        switch readU32(bytes, 0, littleEndian: true) {
        case 0xA1B2C3D4:
            littleEndian = true
            nanoseconds = false
        case 0xA1B23C4D:
            littleEndian = true
            nanoseconds = true
        case 0xD4C3B2A1:
            littleEndian = false
            nanoseconds = false
        case 0x4D3CB2A1:
            littleEndian = false
            nanoseconds = true
        default:
            throw PcapMergeError.notPcap
        }

        let linkType = readU32(bytes, 20, littleEndian: littleEndian)
        var packets: [PcapPacket] = []
        var offset = 24
        while offset + 16 <= bytes.count {
            let seconds = readU32(bytes, offset, littleEndian: littleEndian)
            let fraction = readU32(bytes, offset + 4, littleEndian: littleEndian)
            let captured = Int(readU32(bytes, offset + 8, littleEndian: littleEndian))
            let original = Int(readU32(bytes, offset + 12, littleEndian: littleEndian))
            offset += 16
            guard captured >= 0, offset + captured <= bytes.count else {
                throw PcapMergeError.truncated
            }
            let data = Array(bytes[offset..<offset + captured])
            offset += captured
            let time =
                Double(seconds) + Double(fraction) * (nanoseconds ? 1e-9 : 1e-6)
            packets.append(
                PcapPacket(timestamp: time, data: data, originalLength: original))
        }
        return PcapCapture(linkType: linkType, packets: packets)
    }

    /// Big-endian packet records are still packets; the merge needs numbers,
    /// not a round-trip through the original spelling.
    static func readU32(_ bytes: [UInt8], _ offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        let value: UInt32 =
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        return littleEndian ? value : value.byteSwapped
    }
}

/// One sensor's contribution to a merged trace.
public struct CaptureSource: Equatable, Sendable {
    /// Written as the interface's `if_name`, which is what Wireshark shows for
    /// every frame and what tells two radios apart in one file.
    public let name: String
    /// Written as `if_description`: the host or adapter behind the name.
    public let detail: String?
    public let capture: PcapCapture

    public init(name: String, detail: String? = nil, capture: PcapCapture) {
        self.name = name
        self.detail = detail
        self.capture = capture
    }
}

public struct MergedCapture: Equatable, Sendable {
    public let pcapng: [UInt8]
    /// Sensor name per packet, in merged order, parallel to the file.
    public let packetSensors: [String]
    /// Interface id the writer assigned to each sensor, in IDB order.
    public let interfaceIDs: [String: Int]

    public init(pcapng: [UInt8], packetSensors: [String], interfaceIDs: [String: Int]) {
        self.pcapng = pcapng
        self.packetSensors = packetSensors
        self.interfaceIDs = interfaceIDs
    }

    public var packetCount: Int { packetSensors.count }

    public var sensorNames: [String] {
        packetSensors.reduce(into: [String]()) { names, name in
            if !names.contains(name) { names.append(name) }
        }
    }

    public func sensor(forPacketIndex index: Int) -> String? {
        packetSensors.indices.contains(index) ? packetSensors[index] : nil
    }
}

/// Merges several one-radio pcap captures into one pcapng.
///
/// Each source becomes an interface description block carrying its sensor name
/// (`if_name`) and detail (`if_description`), and packets keep their own
/// interface id, so Wireshark shows which radio saw each frame. Packets are
/// ordered by timestamp across sources — a tie keeps source order, then file
/// order, so the merge is deterministic.
public enum PcapMerge {
    public static func merge(_ sources: [CaptureSource]) throws -> MergedCapture {
        guard !sources.isEmpty else { throw PcapMergeError.noSensors }

        struct Item {
            let timestamp: TimeInterval
            let sourceIndex: Int
            let fileOrder: Int
            let packet: PcapPacket
        }
        var items: [Item] = []
        for (sourceIndex, source) in sources.enumerated() {
            for (fileOrder, packet) in source.capture.packets.enumerated() {
                items.append(
                    Item(
                        timestamp: packet.timestamp, sourceIndex: sourceIndex, fileOrder: fileOrder,
                        packet: packet))
            }
        }
        items.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            if lhs.sourceIndex != rhs.sourceIndex { return lhs.sourceIndex < rhs.sourceIndex }
            return lhs.fileOrder < rhs.fileOrder
        }

        var bytes: [UInt8] = [0x0A, 0x0D, 0x0D, 0x0A]
        appendU32(&bytes, 28)
        appendU32(&bytes, 0x1A2B3C4D)
        appendU16(&bytes, 1)
        appendU16(&bytes, 0)
        appendU64(&bytes, UInt64.max)  // no section length
        appendU32(&bytes, 28)

        var interfaceIDs: [String: Int] = [:]
        for (index, source) in sources.enumerated() {
            interfaceIDs[source.name] = index
            bytes.append(contentsOf: interfaceBlock(source: source))
        }

        var packetSensors: [String] = []
        for item in items {
            bytes.append(
                contentsOf: packetBlock(
                    interfaceID: item.sourceIndex, timestamp: item.packet.timestamp,
                    packet: item.packet))
            packetSensors.append(sources[item.sourceIndex].name)
        }
        return MergedCapture(
            pcapng: bytes, packetSensors: packetSensors, interfaceIDs: interfaceIDs)
    }

    private static func interfaceBlock(source: CaptureSource) -> [UInt8] {
        var body: [UInt8] = []
        appendU16(&body, UInt16(truncatingIfNeeded: source.capture.linkType))
        appendU16(&body, 0)  // reserved
        appendU32(&body, 0)  // snaplen: unspecified
        body.append(contentsOf: option(code: 2, value: source.name))
        if let detail = source.detail, !detail.isEmpty {
            body.append(contentsOf: option(code: 3, value: detail))
        }
        appendU16(&body, 0)  // opt_endofopt
        appendU16(&body, 0)

        var block: [UInt8] = []
        appendU32(&block, 1)  // Interface Description Block
        appendU32(&block, UInt32(12 + body.count))
        block.append(contentsOf: body)
        appendU32(&block, UInt32(12 + body.count))
        return block
    }

    private static func packetBlock(
        interfaceID: Int, timestamp: TimeInterval, packet: PcapPacket
    ) -> [UInt8] {
        let microseconds = UInt64((max(0, timestamp) * 1_000_000).rounded())
        var body: [UInt8] = []
        appendU32(&body, UInt32(interfaceID))
        appendU32(&body, UInt32(truncatingIfNeeded: microseconds >> 32))
        appendU32(&body, UInt32(truncatingIfNeeded: microseconds))
        appendU32(&body, UInt32(packet.data.count))
        appendU32(&body, UInt32(max(packet.originalLength, packet.data.count)))
        body.append(contentsOf: packet.data)
        while body.count % 4 != 0 { body.append(0) }

        var block: [UInt8] = []
        appendU32(&block, 6)  // Enhanced Packet Block
        appendU32(&block, UInt32(12 + body.count))
        block.append(contentsOf: body)
        appendU32(&block, UInt32(12 + body.count))
        return block
    }

    /// pcapng option: code, length, value, padding to a 4-byte boundary.
    private static func option(code: UInt16, value: String) -> [UInt8] {
        let text = Array(value.utf8)
        var bytes: [UInt8] = []
        appendU16(&bytes, code)
        appendU16(&bytes, UInt16(min(text.count, Int(UInt16.max))))
        let length = min(text.count, Int(UInt16.max))
        bytes.append(contentsOf: text.prefix(length))
        while bytes.count % 4 != 0 { bytes.append(0) }
        return bytes
    }

    private static func appendU16(_ bytes: inout [UInt8], _ value: UInt16) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendU32(_ bytes: inout [UInt8], _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            bytes.append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }

    private static func appendU64(_ bytes: inout [UInt8], _ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            bytes.append(UInt8((value >> UInt64(shift)) & 0xFF))
        }
    }
}
