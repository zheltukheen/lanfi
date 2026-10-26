import Foundation

struct CapturedBeacon: Identifiable, Equatable {
    let id: String
    let bssid: String
    let ssid: String
    let channel: Int?
    let rssi: Int?
    let security: String
    let isEHT: Bool
    let informationElements: [InformationElement]
    let clientCount: Int?
    let timestamp: Date
    let source: String
}

enum PcapAnalyzerError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        }
    }
}

/// Offline 802.11 capture reader. Supports classic pcap and pcapng with
/// radiotap (link type 127) or bare 802.11 (105) frames.
enum PcapAnalyzer {
    static func parse(data: Data) throws -> [CapturedBeacon] {
        guard data.count >= 4 else { throw PcapAnalyzerError.unsupported("Capture is too small.") }
        let magic = data.uint32(at: 0, littleEndian: true)
        if magic == 0x0A0D0D0A || data.uint32(at: 0, littleEndian: false) == 0x0A0D0D0A {
            return try parsePcapng(data)
        }
        switch magic {
        case 0xA1B2C3D4, 0xA1B23C4D:
            return try parsePcap(data, littleEndian: true, nanoseconds: magic == 0xA1B23C4D)
        case 0xD4C3B2A1, 0x4D3CB2A1:
            return try parsePcap(data, littleEndian: false, nanoseconds: magic == 0x4D3CB2A1)
        default:
            throw PcapAnalyzerError.unsupported("Not a pcap or pcapng file.")
        }
    }

    // MARK: - Classic pcap

    private static func parsePcap(_ data: Data, littleEndian: Bool, nanoseconds: Bool) throws -> [CapturedBeacon] {
        guard data.count >= 24 else { throw PcapAnalyzerError.unsupported("Truncated pcap header.") }
        let linkType = data.uint32(at: 20, littleEndian: littleEndian)
        guard linkType == 127 || linkType == 105 else {
            throw PcapAnalyzerError.unsupported(
                "This capture uses \(linkTypeName(linkType)), not 802.11 monitor/radiotap. "
                    + "Choose the Wi-Fi monitor interface, not utun/en0 raw IP."
            )
        }
        var offset = 24
        var beacons: [CapturedBeacon] = []
        while offset + 16 <= data.count {
            let seconds = data.uint32(at: offset, littleEndian: littleEndian)
            let fraction = data.uint32(at: offset + 4, littleEndian: littleEndian)
            let included = Int(data.uint32(at: offset + 8, littleEndian: littleEndian))
            offset += 16
            guard included > 0, offset + included <= data.count else { break }
            let packet = data.subdata(in: offset..<(offset + included))
            offset += included
            let timestamp = Date(timeIntervalSince1970: Double(seconds) + Double(fraction) / (nanoseconds ? 1e9 : 1e6))
            if let beacon = parsePacket(packet, linkType: linkType, timestamp: timestamp, source: "pcap") {
                beacons.append(beacon)
            }
        }
        return merge(beacons)
    }

    // MARK: - pcapng

    private static func parsePcapng(_ data: Data) throws -> [CapturedBeacon] {
        var offset = 0
        var littleEndian = true
        var linkTypes: [UInt32] = []
        var beacons: [CapturedBeacon] = []
        var timestampResolution = 1e-6
        var timestampOffset: UInt64 = 0

        while offset + 12 <= data.count {
            let rawType = data.uint32(at: offset, littleEndian: littleEndian)
            var type = rawType
            if rawType == 0x0A0D0D0A {
                if data.uint32(at: offset + 8, littleEndian: true) == 0x1A2B3C4D {
                    littleEndian = true
                } else if data.uint32(at: offset + 8, littleEndian: false) == 0x1A2B3C4D {
                    littleEndian = false
                } else {
                    break
                }
                type = 0x0A0D0D0A
            }
            let length = Int(data.uint32(at: offset + 4, littleEndian: littleEndian))
            guard length >= 12, offset + length <= data.count else { break }
            let bodyStart = offset + 8
            let bodyEnd = offset + length - 4
            switch type {
            case 1:  // Interface Description Block
                if bodyEnd - bodyStart >= 8 {
                    let link = data.uint32(at: bodyStart, littleEndian: littleEndian)
                    linkTypes.append(link)
                    timestampResolution = 1e-6
                    timestampOffset = 0
                    // Parse if_tsresol / if_tsoffset options.
                    var option = bodyStart + 8
                    while option + 4 <= bodyEnd {
                        let code = data.uint16(at: option, littleEndian: littleEndian)
                        let optionLength = Int(data.uint16(at: option + 2, littleEndian: littleEndian))
                        if code == 0 { break }
                        if code == 9, optionLength >= 1, option + 5 <= bodyEnd {
                            let value = data[option + 4]
                            timestampResolution =
                                value & 0x80 == 0 ? pow(10, -Double(value)) : pow(2, -Double(value & 0x7F))
                        } else if code == 14, optionLength >= 8, option + 12 <= bodyEnd {
                            timestampOffset = UInt64(data.uint64(at: option + 4, littleEndian: littleEndian))
                        }
                        option += 4 + optionLength + ((4 - optionLength % 4) % 4)
                    }
                }
            case 6:  // Enhanced Packet Block
                if bodyEnd - bodyStart >= 20 {
                    let interfaceID = Int(data.uint32(at: bodyStart, littleEndian: littleEndian))
                    let high = UInt64(data.uint32(at: bodyStart + 4, littleEndian: littleEndian))
                    let low = UInt64(data.uint32(at: bodyStart + 8, littleEndian: littleEndian))
                    let captured = Int(data.uint32(at: bodyStart + 12, littleEndian: littleEndian))
                    guard bodyStart + 20 + captured <= bodyEnd else { break }
                    let packet = data.subdata(in: (bodyStart + 20)..<(bodyStart + 20 + captured))
                    let ticks = (high << 32) | low
                    let seconds = Double(ticks) * timestampResolution + Double(timestampOffset)
                    let timestamp = Date(timeIntervalSince1970: seconds)
                    let link = linkTypes.indices.contains(interfaceID) ? linkTypes[interfaceID] : 127
                    if let beacon = parsePacket(packet, linkType: link, timestamp: timestamp, source: "pcapng") {
                        beacons.append(beacon)
                    }
                }
            case 3:  // Simple Packet Block
                if bodyEnd - bodyStart >= 8 {
                    let captured = Int(data.uint32(at: bodyStart + 4, littleEndian: littleEndian))
                    let length = min(captured, bodyEnd - bodyStart - 8)
                    let packet = data.subdata(in: (bodyStart + 8)..<(bodyStart + 8 + length))
                    if let beacon = parsePacket(
                        packet, linkType: linkTypes.first ?? 127, timestamp: Date(), source: "pcapng")
                    {
                        beacons.append(beacon)
                    }
                }
            default:
                break
            }
            offset += length
        }
        if beacons.isEmpty, !linkTypes.contains(where: { $0 == 127 || $0 == 105 }),
            let first = linkTypes.first
        {
            throw PcapAnalyzerError.unsupported(
                "This capture uses \(linkTypeName(first)), not 802.11 monitor/radiotap. "
                    + "Choose the Wi-Fi monitor interface."
            )
        }
        return merge(beacons)
    }

    private static func linkTypeName(_ type: UInt32) -> String {
        switch type {
        case 1: return "Ethernet (EN10MB)"
        case 101: return "raw IP (RAW)"
        case 105: return "802.11"
        case 127: return "802.11 + radiotap"
        default: return "link type \(type)"
        }
    }

    // MARK: - Frame parsing

    private static func parsePacket(
        _ packet: Data, linkType: UInt32, timestamp: Date, source: String
    ) -> CapturedBeacon? {
        var frame = packet
        var rssi: Int?
        if linkType == 127 {
            guard let parsed = parseRadiotap(packet) else { return nil }
            frame = packet.subdata(in: parsed.headerLength..<packet.count)
            rssi = parsed.rssi
        }
        guard frame.count >= 36 else { return nil }
        let frameControl = frame.uint16(at: 0, littleEndian: true)
        let type = (frameControl >> 2) & 0x3
        let subtype = (frameControl >> 4) & 0xF
        guard type == 0, subtype == 8 || subtype == 5 else { return nil }
        let bssid = macString(frame, offset: 16)
        guard bssid != "00:00:00:00:00:00" else { return nil }
        let ies = frame.subdata(in: 36..<frame.count)
        var ssid = ""
        var channel: Int?
        var security = "Open"
        var isEHT = false
        let parsedIE = InformationElementParser.parse(ies)
        var index = 0
        while index + 2 <= ies.count {
            let id = ies[index]
            let length = Int(ies[index + 1])
            index += 2
            guard index + length <= ies.count else { break }
            let payload = ies.subdata(in: index..<(index + length))
            index += length
            switch id {
            case 0:
                ssid = String(decoding: payload, as: UTF8.self)
            case 3:
                if let first = payload.first { channel = Int(first) }
            case 48:
                security = rsnSecurity(payload)
            case 191:
                security = "VHT · \(security)"
            case 255:
                if payload.first == 106 || payload.first == 107 { isEHT = true }
            default:
                break
            }
        }
        return CapturedBeacon(
            id: "\(bssid)-\(ssid)",
            bssid: bssid, ssid: ssid.isEmpty ? "Hidden" : ssid,
            channel: channel, rssi: rssi, security: security,
            isEHT: isEHT, informationElements: parsedIE.elements,
            clientCount: parsedIE.clients, timestamp: timestamp, source: source
        )
    }

    private static func parseRadiotap(_ packet: Data) -> (headerLength: Int, rssi: Int?)? {
        guard packet.count >= 8, packet[0] == 0 else { return nil }
        let headerLength = Int(packet.uint16(at: 2, littleEndian: true))
        guard headerLength >= 8, headerLength <= packet.count else { return nil }
        let present = packet.uint32(at: 4, littleEndian: true)
        var offset = 8
        var rssi: Int?
        for bit in 0..<32 {
            guard present & (1 << UInt32(bit)) != 0 else { continue }
            let alignment: Int
            let size: Int
            switch bit {
            case 0: alignment = 8; size = 8
            case 1, 2: alignment = 1; size = 1
            case 3: alignment = 2; size = 4
            case 4: alignment = 2; size = 2
            case 5: alignment = 1; size = 1
            case 6, 7: alignment = 1; size = 1
            case 8, 9, 10: alignment = 2; size = 2
            case 11: alignment = 1; size = 1
            case 12, 13: alignment = 1; size = 1
            case 14, 15: alignment = 2; size = 2
            case 16, 17: alignment = 1; size = 1
            case 18: alignment = 4; size = 8
            case 19: alignment = 1; size = 3
            case 20: alignment = 4; size = 8
            case 21: alignment = 2; size = 12
            case 22: alignment = 8; size = 12
            case 23, 24: alignment = 2; size = 12
            default: return (headerLength, rssi)
            }
            offset = (offset + alignment - 1) & ~(alignment - 1)
            guard offset + size <= headerLength else { return (headerLength, rssi) }
            if bit == 5 {
                rssi = Int(Int8(bitPattern: packet[offset]))
            }
            offset += size
        }
        return (headerLength, rssi)
    }

    private static func rsnSecurity(_ data: Data) -> String {
        guard data.count >= 8 else { return "WPA2" }
        var index = 2
        guard index + 4 <= data.count else { return "WPA2" }
        index += 4  // group cipher
        guard index + 2 <= data.count else { return "WPA2" }
        let pairwiseCount = Int(data.uint16(at: index, littleEndian: true))
        index += 2 + pairwiseCount * 4
        guard index + 2 <= data.count else { return "WPA2" }
        let akmCount = Int(data.uint16(at: index, littleEndian: true))
        index += 2
        var hasSAE = false
        var hasPSK = false
        for _ in 0..<akmCount {
            guard index + 4 <= data.count else { break }
            let akm = data.uint32(at: index, littleEndian: true)
            if akm == 8 || akm == 9 { hasSAE = true }
            if akm == 2 || akm == 4 { hasPSK = true }
            index += 4
        }
        if hasSAE && hasPSK { return "WPA3 Transition" }
        if hasSAE { return "WPA3 Personal" }
        return "WPA2 Personal"
    }

    private static func merge(_ beacons: [CapturedBeacon]) -> [CapturedBeacon] {
        var merged: [String: CapturedBeacon] = [:]
        for beacon in beacons {
            if let existing = merged[beacon.id] {
                if (beacon.rssi ?? -999) > (existing.rssi ?? -999) {
                    merged[beacon.id] = beacon
                }
            } else {
                merged[beacon.id] = beacon
            }
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.ssid != rhs.ssid { return lhs.ssid.localizedStandardCompare(rhs.ssid) == .orderedAscending }
            return lhs.bssid < rhs.bssid
        }
    }

    private static func macString(_ data: Data, offset: Int) -> String {
        guard offset + 6 <= data.count else { return "00:00:00:00:00:00" }
        return (0..<6).map { String(format: "%02X", data[offset + $0]) }.joined(separator: ":")
    }
}

private extension Data {
    func uint16(at offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        return littleEndian ? UInt16(littleEndian: value) : UInt16(bigEndian: value)
    }

    func uint32(at offset: Int, littleEndian: Bool) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return littleEndian ? UInt32(littleEndian: value) : UInt32(bigEndian: value)
    }

    func uint64(at offset: Int, littleEndian: Bool) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
        return littleEndian ? UInt64(littleEndian: value) : UInt64(bigEndian: value)
    }
}

struct CapturedClient: Identifiable, Equatable {
    let id: String
    let mac: String
    let bssid: String
    let frameCount: Int
    let isAccessPoint: Bool
}

extension PcapAnalyzer {
    static func clients(data: Data) throws -> [CapturedClient] {
        let beacons = try parse(data: data)
        let accessPointMACs = Set(beacons.map(\.bssid))
        let packets = try rawPackets(data)
        var counts: [String: (bssid: String, frames: Int)] = [:]
        for (linkType, packet, _) in packets {
            guard linkType == 127 || linkType == 105 else { continue }
            var frame = packet
            if linkType == 127 {
                guard let headerLength = radiotapHeaderLength(packet), headerLength < packet.count else { continue }
                frame = packet.subdata(in: headerLength..<packet.count)
            }
            guard frame.count >= 24 else { continue }
            let fc = frame.uint16(at: 0, littleEndian: true)
            let type = (fc >> 2) & 0x3
            guard type == 0 || type == 2 else { continue }
            let address1 = mac(frame, offset: 4)
            let address2 = mac(frame, offset: 10)
            let address3 = mac(frame, offset: 16)
            let candidates = [address1, address2, address3].filter { mac in
                !mac.isEmpty && mac != "FF:FF:FF:FF:FF:FF" && !isMulticast(mac)
            }
            let bssid =
                candidates.first { accessPointMACs.contains($0) }
                ?? (type == 0 ? address3 : address1)
            guard !candidates.isEmpty, bssid != "00:00:00:00:00:00" else { continue }
            for address in candidates where address != bssid {
                var entry = counts[address] ?? (bssid, 0)
                entry.frames += 1
                counts[address] = entry
            }
        }
        return counts.map {
            CapturedClient(
                id: $0.key, mac: $0.key, bssid: $0.value.bssid,
                frameCount: $0.value.frames, isAccessPoint: false
            )
        }.sorted { $0.frameCount > $1.frameCount }
    }

    private static func rawPackets(_ data: Data) throws -> [(UInt32, Data, Date)] {
        guard data.count >= 4 else { throw PcapAnalyzerError.unsupported("Capture is too small.") }
        let magic = data.uint32(at: 0, littleEndian: true)
        if magic == 0x0A0D0D0A || data.uint32(at: 0, littleEndian: false) == 0x0A0D0D0A {
            return try rawPcapngPackets(data)
        }
        switch magic {
        case 0xA1B2C3D4, 0xA1B23C4D:
            return try rawPcapPackets(data, littleEndian: true, nanoseconds: magic == 0xA1B23C4D)
        case 0xD4C3B2A1, 0x4D3CB2A1:
            return try rawPcapPackets(data, littleEndian: false, nanoseconds: magic == 0x4D3CB2A1)
        default:
            throw PcapAnalyzerError.unsupported("Not a pcap or pcapng file.")
        }
    }

    private static func rawPcapPackets(
        _ data: Data, littleEndian: Bool, nanoseconds: Bool
    ) throws -> [(UInt32, Data, Date)] {
        guard data.count >= 24 else { throw PcapAnalyzerError.unsupported("Truncated pcap header.") }
        let linkType = data.uint32(at: 20, littleEndian: littleEndian)
        var offset = 24
        var packets: [(UInt32, Data, Date)] = []
        while offset + 16 <= data.count {
            let seconds = data.uint32(at: offset, littleEndian: littleEndian)
            let fraction = data.uint32(at: offset + 4, littleEndian: littleEndian)
            let included = Int(data.uint32(at: offset + 8, littleEndian: littleEndian))
            offset += 16
            guard included > 0, offset + included <= data.count else { break }
            let packet = data.subdata(in: offset..<(offset + included))
            offset += included
            let timestamp = Date(
                timeIntervalSince1970: Double(seconds) + Double(fraction) / (nanoseconds ? 1e9 : 1e6)
            )
            packets.append((linkType, packet, timestamp))
        }
        return packets
    }

    private static func rawPcapngPackets(_ data: Data) throws -> [(UInt32, Data, Date)] {
        var offset = 0
        var littleEndian = true
        var linkTypes: [UInt32] = []
        var packets: [(UInt32, Data, Date)] = []
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
            } else if type == 6, bodyEnd - bodyStart >= 20 {
                let interfaceID = Int(data.uint32(at: bodyStart, littleEndian: littleEndian))
                let high = UInt64(data.uint32(at: bodyStart + 4, littleEndian: littleEndian))
                let low = UInt64(data.uint32(at: bodyStart + 8, littleEndian: littleEndian))
                let captured = Int(data.uint32(at: bodyStart + 12, littleEndian: littleEndian))
                if bodyStart + 20 + captured <= bodyEnd {
                    let packet = data.subdata(in: (bodyStart + 20)..<(bodyStart + 20 + captured))
                    let ticks = (high << 32) | low
                    let seconds = Double(ticks) * timestampResolution + Double(timestampOffset)
                    let link = linkTypes.indices.contains(interfaceID) ? linkTypes[interfaceID] : 127
                    packets.append((link, packet, Date(timeIntervalSince1970: seconds)))
                }
            }
            offset += length
        }
        return packets
    }

    private static func radiotapHeaderLength(_ packet: Data) -> Int? {
        guard packet.count >= 8, packet[0] == 0 else { return nil }
        let length = Int(packet.uint16(at: 2, littleEndian: true))
        return (8...packet.count).contains(length) ? length : nil
    }

    private static func mac(_ data: Data, offset: Int) -> String {
        guard offset + 6 <= data.count else { return "" }
        return (0..<6).map { String(format: "%02X", data[offset + $0]) }.joined(separator: ":")
    }

    private static func isMulticast(_ mac: String) -> Bool {
        guard let first = UInt8(mac.prefix(2), radix: 16) else { return false }
        return first & 0x01 != 0
    }
}
