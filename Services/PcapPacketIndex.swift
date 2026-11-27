import Foundation

/// Header-only index of a pcap/pcapng capture.
///
/// Packet bytes are not copied during indexing: only the file offset, length,
/// link type and timestamp are stored. Parsing then slices one packet at a time
/// and lets it go, which keeps the peak memory close to the mapped file size
/// instead of a second array of every packet.
struct PcapPacketIndex: Sequence {
    struct Entry {
        let offset: Int
        let length: Int
        let linkType: UInt32
        let timestamp: Date
        /// The capture interface's name (`if_name`), which is the sensor name
        /// in a file merged from several sensors. Nil for classic pcap and for
        /// pcapng files written without the option.
        let sensor: String?
    }

    struct Iterator: IteratorProtocol {
        let data: Data
        let entries: [Entry]
        var index = 0

        mutating func next() -> (UInt32, Data, Date, String?)? {
            guard index < entries.count else { return nil }
            let entry = entries[index]
            index += 1
            guard entry.offset + entry.length <= data.count else { return next() }
            return (
                entry.linkType,
                data.subdata(in: entry.offset..<(entry.offset + entry.length)),
                entry.timestamp, entry.sensor
            )
        }
    }

    let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        guard data.count >= 4 else {
            throw PcapAnalyzerError.unsupported("Capture is too small.")
        }
        let magic = data.uint32(at: 0, littleEndian: true)
        if magic == 0x0A0D0D0A || data.uint32(at: 0, littleEndian: false) == 0x0A0D0D0A {
            entries = try Self.indexPcapng(data)
        } else {
            switch magic {
            case 0xA1B2C3D4, 0xA1B23C4D:
                entries = try Self.indexPcap(
                    data, littleEndian: true, nanoseconds: magic == 0xA1B23C4D)
            case 0xD4C3B2A1, 0x4D3CB2A1:
                entries = try Self.indexPcap(
                    data, littleEndian: false, nanoseconds: magic == 0x4D3CB2A1)
            default:
                throw PcapAnalyzerError.unsupported("Not a pcap or pcapng file.")
            }
        }
    }

    func makeIterator() -> Iterator {
        Iterator(data: data, entries: entries)
    }

    private static func indexPcap(
        _ data: Data, littleEndian: Bool, nanoseconds: Bool
    ) throws -> [Entry] {
        guard data.count >= 24 else {
            throw PcapAnalyzerError.unsupported("Truncated pcap header.")
        }
        let linkType = data.uint32(at: 20, littleEndian: littleEndian)
        var offset = 24
        var entries: [Entry] = []
        while offset + 16 <= data.count {
            let seconds = data.uint32(at: offset, littleEndian: littleEndian)
            let fraction = data.uint32(at: offset + 4, littleEndian: littleEndian)
            let included = Int(data.uint32(at: offset + 8, littleEndian: littleEndian))
            offset += 16
            guard included > 0, offset + included <= data.count else { break }
            let timestamp = Date(
                timeIntervalSince1970: Double(seconds)
                    + Double(fraction) / (nanoseconds ? 1e9 : 1e6))
            entries.append(
                Entry(
                    offset: offset, length: included, linkType: linkType, timestamp: timestamp,
                    sensor: nil))
            offset += included
        }
        return entries
    }

    private static func indexPcapng(_ data: Data) throws -> [Entry] {
        var offset = 0
        var littleEndian = true
        var linkTypes: [UInt32] = []
        var interfaceNames: [String?] = []
        var entries: [Entry] = []
        var timestampResolution = 1e-6
        var timestampOffset: UInt64 = 0

        while offset + 12 <= data.count {
            let rawType = data.uint32(at: offset, littleEndian: littleEndian)
            if rawType == 0x0A0D0D0A {
                if data.uint32(at: offset + 8, littleEndian: true) == 0x1A2B3C4D {
                    littleEndian = true
                } else if data.uint32(at: offset + 8, littleEndian: false) == 0x1A2B3C4D {
                    littleEndian = false
                } else {
                    break
                }
            }
            let type = data.uint32(at: offset, littleEndian: littleEndian)
            let length = Int(data.uint32(at: offset + 4, littleEndian: littleEndian))
            guard length >= 12, offset + length <= data.count else { break }
            let bodyStart = offset + 8
            let bodyEnd = offset + length - 4

            if type == 1, bodyEnd - bodyStart >= 8 {
                linkTypes.append(data.uint32(at: bodyStart, littleEndian: littleEndian))
                timestampResolution = 1e-6
                timestampOffset = 0
                var name: String?
                var option = bodyStart + 8
                while option + 4 <= bodyEnd {
                    let code = data.uint16(at: option, littleEndian: littleEndian)
                    let optionLength = Int(data.uint16(at: option + 2, littleEndian: littleEndian))
                    if code == 0 { break }
                    if code == 2, optionLength > 0, option + 4 + optionLength <= bodyEnd {
                        let bytes = data.subdata(
                            in: (option + 4)..<(option + 4 + optionLength))
                        let text = String(decoding: bytes, as: UTF8.self)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                        name = text.isEmpty ? nil : text
                    } else if code == 9, optionLength >= 1, option + 5 <= bodyEnd {
                        let value = data[option + 4]
                        timestampResolution =
                            value & 0x80 == 0
                            ? pow(10, -Double(value)) : pow(2, -Double(value & 0x7F))
                    } else if code == 14, optionLength >= 8, option + 12 <= bodyEnd {
                        timestampOffset = UInt64(
                            data.uint64(at: option + 4, littleEndian: littleEndian))
                    }
                    option += 4 + optionLength + ((4 - optionLength % 4) % 4)
                }
                interfaceNames.append(name)
            } else if type == 6, bodyEnd - bodyStart >= 20 {
                let interfaceID = Int(data.uint32(at: bodyStart, littleEndian: littleEndian))
                let high = UInt64(data.uint32(at: bodyStart + 4, littleEndian: littleEndian))
                let low = UInt64(data.uint32(at: bodyStart + 8, littleEndian: littleEndian))
                let captured = Int(data.uint32(at: bodyStart + 12, littleEndian: littleEndian))
                if bodyStart + 20 + captured <= bodyEnd {
                    let ticks = (high << 32) | low
                    let seconds = Double(ticks) * timestampResolution + Double(timestampOffset)
                    let link = linkTypes.indices.contains(interfaceID) ? linkTypes[interfaceID] : 127
                    let sensor =
                        interfaceNames.indices.contains(interfaceID)
                        ? interfaceNames[interfaceID] : nil
                    entries.append(
                        Entry(
                            offset: bodyStart + 20, length: captured, linkType: link,
                            timestamp: Date(timeIntervalSince1970: seconds), sensor: sensor))
                }
            } else if type == 3, bodyEnd - bodyStart >= 8 {
                let captured = Int(data.uint32(at: bodyStart + 4, littleEndian: littleEndian))
                let length = Swift.min(captured, bodyEnd - bodyStart - 8)
                entries.append(
                    Entry(
                        offset: bodyStart + 8, length: length,
                        linkType: linkTypes.first ?? 127, timestamp: Date(),
                        sensor: interfaceNames.first ?? nil))
            }
            offset += length
        }
        return entries
    }
}
