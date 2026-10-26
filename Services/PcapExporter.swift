import Foundation

/// Exports scan results as a valid pcap containing synthetic 802.11 beacon
/// frames. CoreWLAN does not expose received frames, so this is an offline
/// reconstruction of each advertised beacon — not a live packet capture.
/// It is deliberately labelled "synthetic" in the UI.
enum PcapExporter {
    static let linkTypeIEEE80211Radiotap: UInt32 = 127

    static func makeCapture(networks: [NetworkModel], timestamp: Date = Date()) -> Data {
        var data = Data()
        data.append(contentsOf: globalHeader())

        for (index, network) in networks.enumerated() {
            guard let frame = beaconFrame(for: network) else { continue }
            var radiotap = Data([0x00, 0x00])  // version, pad
            radiotap.append(littleEndian: UInt16(8))  // header length
            radiotap.append(littleEndian: UInt32(0))  // present flags
            let packet = radiotap + frame
            let seconds = UInt32(timestamp.timeIntervalSince1970) + UInt32(index)
            let microseconds = UInt32((timestamp.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1_000_000)
            data.append(
                packetHeader(
                    seconds: seconds,
                    microseconds: microseconds,
                    includedLength: UInt32(packet.count),
                    originalLength: UInt32(packet.count)
                ))
            data.append(packet)
        }
        return data
    }

    static func makePcapngCapture(networks: [NetworkModel], timestamp: Date = Date()) -> Data {
        var data = Data()
        data.append(contentsOf: sectionHeader())
        data.append(contentsOf: interfaceDescription())
        let microfraction = UInt64(timestamp.timeIntervalSince1970 * 1_000_000)
        for (index, network) in networks.enumerated() {
            guard let frame = beaconFrame(for: network) else { continue }
            var radiotap = Data([0x00, 0x00])
            radiotap.append(littleEndian: UInt16(8))
            radiotap.append(littleEndian: UInt32(0))
            let packet = radiotap + frame
            let ticks = microfraction + UInt64(index) * 1_000_000
            data.append(
                enhancedPacket(
                    timestampMicroseconds: ticks,
                    packet: packet
                ))
        }
        return data
    }

    static func beaconFrame(for network: NetworkModel) -> Data? {
        guard let bssid = macBytes(network.bssid) ?? macBytes("02:00:00:00:00:01") else {
            return nil
        }

        var frame = Data()
        frame.append(littleEndian: UInt16(0x0080))  // beacon
        frame.append(littleEndian: UInt16(0))  // duration
        frame.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])  // broadcast
        frame.append(contentsOf: bssid)
        frame.append(contentsOf: bssid)
        frame.append(littleEndian: UInt16(0))  // sequence control
        frame.append(contentsOf: [UInt8](repeating: 0, count: 8))  // timestamp
        frame.append(littleEndian: UInt16(network.beaconInterval ?? 100))
        frame.append(littleEndian: capability(for: network))

        let ssid = Data(network.ssid.utf8)
        frame.append(ie(id: 0, payload: ssid))

        if let width = network.channelWidthMHz as Int?, width > 0, network.channel > 0 {
            frame.append(ie(id: 3, payload: Data([UInt8(clamping: network.channel)])))
        }

        if let rates = network.basicRates, !rates.isEmpty {
            let payload = rates.prefix(8).map { UInt8(clamping: Int($0 * 2)) }
            frame.append(ie(id: 1, payload: Data(payload)))
        }

        return frame
    }

    // MARK: - Headers

    private static func globalHeader() -> Data {
        var data = Data()
        data.append(littleEndian: UInt32(0xA1B2C3D4))
        data.append(littleEndian: UInt16(2))
        data.append(littleEndian: UInt16(4))
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: UInt32(0))
        data.append(littleEndian: UInt32(65_535))
        data.append(littleEndian: linkTypeIEEE80211Radiotap)
        return data
    }

    private static func sectionHeader() -> Data {
        var body = Data()
        body.append(littleEndian: UInt32(0x1A2B3C4D))
        body.append(littleEndian: UInt16(1))
        body.append(littleEndian: UInt16(0))
        body.append(littleEndian: Int64(-1))
        var block = Data()
        block.append(littleEndian: UInt32(0x0A0D0D0A))
        block.append(littleEndian: UInt32(28))
        block.append(body)
        block.append(littleEndian: UInt32(28))
        return block
    }

    private static func interfaceDescription() -> Data {
        var body = Data()
        body.append(littleEndian: UInt16(127))
        body.append(littleEndian: UInt16(0))
        body.append(littleEndian: UInt32(65_535))
        var block = Data()
        block.append(littleEndian: UInt32(1))
        block.append(littleEndian: UInt32(20))
        block.append(body)
        block.append(littleEndian: UInt32(20))
        return block
    }

    private static func enhancedPacket(timestampMicroseconds: UInt64, packet: Data) -> Data {
        var body = Data()
        body.append(littleEndian: UInt32(0))  // interface id
        body.append(littleEndian: UInt32(timestampMicroseconds >> 32))
        body.append(littleEndian: UInt32(timestampMicroseconds & 0xFFFF_FFFF))
        body.append(littleEndian: UInt32(packet.count))
        body.append(littleEndian: UInt32(packet.count))
        body.append(packet)
        while body.count % 4 != 0 { body.append(0) }
        let total = UInt32(12 + body.count)
        var block = Data()
        block.append(littleEndian: UInt32(6))
        block.append(littleEndian: total)
        block.append(body)
        block.append(littleEndian: total)
        return block
    }

    private static func packetHeader(
        seconds: UInt32,
        microseconds: UInt32,
        includedLength: UInt32,
        originalLength: UInt32
    ) -> Data {
        var data = Data()
        data.append(littleEndian: seconds)
        data.append(littleEndian: microseconds)
        data.append(littleEndian: includedLength)
        data.append(littleEndian: originalLength)
        return data
    }

    private static func ie(id: UInt8, payload: Data) -> Data {
        var data = Data([id, UInt8(clamping: payload.count)])
        data.append(payload)
        return data
    }

    private static func capability(for network: NetworkModel) -> UInt16 {
        var value: UInt16 = 0x0001  // ESS
        if !network.security.lowercased().contains("open") {
            value |= 0x0010  // privacy
        }
        return value
    }

    private static func macBytes(_ value: String) -> Data? {
        let hex = value.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
