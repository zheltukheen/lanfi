import Foundation

/// P2 — iBeacon/Eddystone decoding from CoreBluetooth advertisement data.
/// Only advertisement payloads are read; no connection is made and nothing is
/// written to the device.
enum BeaconKind: String, Equatable {
    case iBeacon
    case eddystoneUID
    case eddystoneURL
    case eddystoneTLM
    case other

    var label: String { rawValue }
}

struct BLEBeacon: Identifiable, Equatable {
    let id: String
    var name: String
    var rssi: Int
    var kind: BeaconKind
    var detail: String
    var url: String?
    var minor: Int?
    var major: Int?
    var namespaceID: String?
    var instanceID: String?
    var txPower: Int?
    var lastSeen: Date
}

enum BLEBeaconParser {
    static let appleCompanyID: UInt16 = 0x004C
    static let eddystoneServiceUUID = "FEAA"

    /// Apple iBeacon manufacturer data: `4C 00 02 15` + UUID(16) +
    /// major(2) + minor(2) + measured power(1).
    static func iBeacon(
        manufacturerData: Data, name: String, rssi: Int, id: String, at date: Date = Date()
    ) -> BLEBeacon? {
        let bytes = [UInt8](manufacturerData)
        guard bytes.count >= 25,
            bytes[0] == 0x4C, bytes[1] == 0x00, bytes[2] == 0x02, bytes[3] == 0x15
        else { return nil }
        let uuid = formatUUID(Array(bytes[4..<20]))
        let major = Int(bytes[20]) << 8 | Int(bytes[21])
        let minor = Int(bytes[22]) << 8 | Int(bytes[23])
        let txPower = Int(Int8(bitPattern: bytes[24]))
        return BLEBeacon(
            id: id,
            name: name,
            rssi: rssi,
            kind: .iBeacon,
            detail: "\(uuid) · major \(major) · minor \(minor)",
            url: nil,
            minor: minor,
            major: major,
            namespaceID: nil,
            instanceID: nil,
            txPower: txPower,
            lastSeen: date
        )
    }

    /// Eddystone service data for service `FEAA`. Frame type 0x00 is UID,
    /// 0x10 URL and 0x20 telemetry.
    static func eddystone(
        serviceData: Data, name: String, rssi: Int, id: String, at date: Date = Date()
    ) -> BLEBeacon? {
        let bytes = [UInt8](serviceData)
        guard let frameType = bytes.first else { return nil }
        switch frameType {
        case 0x00:
            guard bytes.count >= 18 else { return nil }
            let namespace = bytes[2..<12].map { String(format: "%02X", $0) }.joined()
            let instance = bytes[12..<18].map { String(format: "%02X", $0) }.joined()
            return BLEBeacon(
                id: id, name: name, rssi: rssi, kind: .eddystoneUID,
                detail: "\(namespace) · \(instance)", url: nil, minor: nil, major: nil,
                namespaceID: namespace, instanceID: instance,
                txPower: Int(Int8(bitPattern: bytes[1])), lastSeen: date)
        case 0x10:
            guard bytes.count >= 3 else { return nil }
            let url = decodeURL(Array(bytes[2...]))
            return BLEBeacon(
                id: id, name: name, rssi: rssi, kind: .eddystoneURL,
                detail: url, url: url, minor: nil, major: nil, namespaceID: nil,
                instanceID: nil, txPower: Int(Int8(bitPattern: bytes[1])), lastSeen: date)
        case 0x20:
            guard bytes.count >= 14 else { return nil }
            let voltage = Int(bytes[2]) << 8 | Int(bytes[3])
            let rawTemperature = Int16(bitPattern: UInt16(bytes[4]) << 8 | UInt16(bytes[5]))
            let temperature = Double(rawTemperature) / 256.0
            return BLEBeacon(
                id: id, name: name, rssi: rssi, kind: .eddystoneTLM,
                detail:
                    "\(voltage / 1000).\(String(format: "%03d", voltage % 1000)) V · \(String(format: "%.1f", temperature)) °C",
                url: nil, minor: nil, major: nil, namespaceID: nil, instanceID: nil,
                txPower: nil, lastSeen: date)
        default:
            return nil
        }
    }

    static func decodeURL(_ encoded: [UInt8]) -> String {
        let schemes = [
            "http://www.", "https://www.", "http://", "https://",
        ]
        let expansions: [UInt8: String] = [
            0x00: ".com/", 0x01: ".org/", 0x02: ".edu/", 0x03: ".net/",
            0x04: ".info/", 0x05: ".biz/", 0x06: ".gov/", 0x07: ".com",
            0x08: ".org", 0x09: ".edu", 0x0A: ".net", 0x0B: ".info",
            0x0C: ".biz", 0x0D: ".gov",
        ]
        guard let first = encoded.first, Int(first) < schemes.count else { return "" }
        var result = schemes[Int(first)]
        for byte in encoded.dropFirst() {
            if let expansion = expansions[byte] {
                result += expansion
            } else if byte >= 0x20, byte < 0x7F {
                result.append(Character(UnicodeScalar(byte)))
            }
        }
        return result
    }

    private static func formatUUID(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        guard hex.count == 32 else { return hex }
        return [
            hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4),
            hex.dropFirst(16).prefix(4), hex.dropFirst(20),
        ].map(String.init).joined(separator: "-")
    }
}

/// Zigbee shares 2.4 GHz with Wi-Fi. This is a coexistence map, not a Zigbee
/// radio: no 802.15.4 adapter is driven by LanFi.
enum ZigbeeCoexistence {
    /// Zigbee channels 11…26, 5 MHz apart from 2405 MHz.
    static func frequencyMHz(channel: Int) -> Int? {
        guard (11...26).contains(channel) else { return nil }
        return 2405 + (channel - 11) * 5
    }

    /// Wi-Fi 2.4 GHz channels whose 20 MHz width overlaps the Zigbee channel.
    static func overlappingWiFiChannels(zigbeeChannel: Int) -> [Int] {
        guard let frequency = frequencyMHz(channel: zigbeeChannel) else { return [] }
        return (1...14).filter { wifiChannel in
            let center = wifiCenterMHz(channel: wifiChannel)
            return abs(center - frequency) < 22
        }
    }

    /// Zigbee channels clear of the common non-overlapping Wi-Fi plan
    /// (1, 6, 11), allowing 10 MHz for a Wi-Fi channel and 1 MHz for Zigbee.
    static var quietChannels: [Int] {
        let plan = [1, 6, 11]
        return (11...26).filter { zigbee in
            guard let frequency = frequencyMHz(channel: zigbee) else { return false }
            return plan.allSatisfy { wifi in
                abs(Double(wifiCenterMHz(channel: wifi) - frequency)) >= 11
            }
        }
    }

    static func wifiCenterMHz(channel: Int) -> Int {
        channel == 14 ? 2484 : 2407 + channel * 5
    }
}
