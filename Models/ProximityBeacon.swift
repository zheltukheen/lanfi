import Foundation

struct ProximityBeaconInfo: Equatable {
    let uuid: String
    let major: Int
    let minor: Int
    let txPower: Int

    static func parse(_ element: InformationElement) -> ProximityBeaconInfo? {
        let bytes = element.rawHex.split(whereSeparator: \.isWhitespace).compactMap { UInt8($0, radix: 16) }
        guard bytes.count >= 23 else { return nil }
        // Apple iBeacon vendor IE: 4C 00 02 15, UUID(16), major(2), minor(2), txPower(1)
        guard bytes[0] == 0x4C, bytes[1] == 0x00, bytes[2] == 0x02, bytes[3] == 0x15 else { return nil }
        let uuidBytes = Array(bytes[4..<20])
        let uuid = formatUUID(uuidBytes)
        let major = Int(bytes[20]) << 8 | Int(bytes[21])
        let minor = Int(bytes[22]) << 8 | Int(bytes[23])
        let txPower = Int(Int8(bitPattern: bytes[24]))
        return ProximityBeaconInfo(uuid: uuid, major: major, minor: minor, txPower: txPower)
    }

    static func find(in elements: [InformationElement]) -> ProximityBeaconInfo? {
        elements.compactMap(parse).first
    }

    private static func formatUUID(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        guard hex.count == 32 else { return hex }
        let parts = [
            hex.prefix(8),
            hex.dropFirst(8).prefix(4),
            hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4),
            hex.dropFirst(20),
        ]
        return parts.map(String.init).joined(separator: "-")
    }
}
