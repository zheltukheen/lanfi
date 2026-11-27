import Foundation

/// P2 — read-only SNMP v2c GET. Just enough BER to read standard interface
/// counters and the system name; no SET, no traps, no table walks beyond a
/// fixed OID list. The community is supplied per request and never stored.
enum SNMPOID {
    static let systemName = "1.3.6.1.2.1.1.5.0"
    static let systemDescription = "1.3.6.1.2.1.1.1.0"
    static let interfaceDescription = "1.3.6.1.2.1.2.2.1.2"
    static let interfaceInOctets = "1.3.6.1.2.1.2.2.1.10"
    static let interfaceOutOctets = "1.3.6.1.2.1.2.2.1.16"

    static let standardCounters = [
        systemName, systemDescription, interfaceDescription, interfaceInOctets,
        interfaceOutOctets,
    ]
}

enum SNMPValue: Equatable {
    case integer(Int64)
    case counter(UInt64)
    case string(String)
    case null
    case bytes([UInt8])
    /// The agent has nothing past this OID; a walk stops here.
    case endOfMibView

    var number: UInt64? {
        switch self {
        case .integer(let value): return value >= 0 ? UInt64(value) : nil
        case .counter(let value): return value
        default: return nil
        }
    }

    var text: String {
        switch self {
        case .integer(let value): return "\(value)"
        case .counter(let value): return "\(value)"
        case .string(let value): return value
        case .null: return "—"
        case .bytes(let value): return value.map { String(format: "%02X", $0) }.joined()
        case .endOfMibView: return "—"
        }
    }
}

enum SNMPBER {
    static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        if length <= 0xFF { return [0x81, UInt8(length)] }
        return [0x82, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
    }

    static func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        [tag] + encodeLength(body.count) + body
    }

    static func integer(_ value: Int) -> [UInt8] {
        var bytes = withUnsafeBytes(of: Int64(value).bigEndian) { Array($0) }
        while bytes.count > 1, bytes.first == 0, bytes[1] & 0x80 == 0 { bytes.removeFirst() }
        while bytes.count > 1, bytes.first == 0xFF, bytes[1] & 0x80 != 0 { bytes.removeFirst() }
        return tlv(0x02, bytes)
    }

    static func octetString(_ value: String) -> [UInt8] {
        tlv(0x04, Array(value.utf8))
    }

    static func null() -> [UInt8] { [0x05, 0x00] }

    static func oid(_ text: String) -> [UInt8]? {
        let components = text.split(separator: ".").compactMap { Int($0) }
        guard components.count >= 2, components.allSatisfy({ $0 >= 0 }),
            components[0] <= 2, components[1] < 40
        else { return nil }
        var body: [UInt8] = [UInt8(components[0] * 40 + components[1])]
        for component in components.dropFirst(2) {
            var value = component
            var encoded: [UInt8] = [UInt8(value & 0x7F)]
            value >>= 7
            while value > 0 {
                encoded.insert(UInt8((value & 0x7F) | 0x80), at: 0)
                value >>= 7
            }
            body.append(contentsOf: encoded)
        }
        return tlv(0x06, body)
    }

    /// SNMPv2c GetRequest for the given OIDs.
    static func getRequest(
        community: String, oids: [String], requestID: Int = Int.random(in: 1...Int(Int32.max))
    ) -> [UInt8] {
        request(pduTag: 0xA0, community: community, oids: oids, requestID: requestID)
    }

    /// SNMPv2c GetNextRequest: the primitive a table walk is built from.
    static func getNextRequest(
        community: String, oids: [String], requestID: Int = Int.random(in: 1...Int(Int32.max))
    ) -> [UInt8] {
        request(pduTag: 0xA1, community: community, oids: oids, requestID: requestID)
    }

    private static func request(
        pduTag: UInt8, community: String, oids: [String], requestID: Int
    ) -> [UInt8] {
        let bindings = oids.compactMap { oid($0) }.map { tlv(0x30, $0 + null()) }
        let pdu = tlv(
            pduTag,
            integer(requestID) + integer(0) + integer(0)
                + tlv(0x30, bindings.flatMap { $0 }))
        return tlv(0x30, integer(1) + octetString(community) + pdu)
    }

    struct TLV {
        let tag: UInt8
        let body: [UInt8]
    }

    static func parseTLV(_ bytes: [UInt8], at offset: Int) -> (TLV, Int)? {
        guard offset < bytes.count else { return nil }
        let tag = bytes[offset]
        var index = offset + 1
        guard index < bytes.count else { return nil }
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard count >= 1, count <= 4, index + count <= bytes.count else { return nil }
            length = 0
            for _ in 0..<count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { return nil }
        return (TLV(tag: tag, body: Array(bytes[index..<index + length])), index + length)
    }

    static func decodeOID(_ body: [UInt8]) -> String {
        guard let first = body.first else { return "" }
        var components = [Int(first) / 40, Int(first) % 40]
        var value = 0
        for byte in body.dropFirst() {
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                components.append(value)
                value = 0
            }
        }
        return components.map(String.init).joined(separator: ".")
    }

    /// Parses a GetResponse into OID → value. Unknown PDUs and malformed
    /// variable bindings are skipped rather than guessed.
    static func parseResponse(_ bytes: [UInt8]) -> [String: SNMPValue] {
        var result: [String: SNMPValue] = [:]
        for binding in parseVarBinds(bytes) {
            result[binding.oid] = binding.value
        }
        return result
    }

    /// The same response in the order the agent sent it, which a walk needs:
    /// duplicates and ordering are meaningful when advancing the cursor.
    static func parseVarBinds(_ bytes: [UInt8]) -> [(oid: String, value: SNMPValue)] {
        guard let (outer, _) = parseTLV(bytes, at: 0), outer.tag == 0x30 else {
            return []
        }
        var index = 0
        var fields: [TLV] = []
        while index < outer.body.count, let (field, next) = parseTLV(outer.body, at: index) {
            fields.append(field)
            index = next
        }
        guard fields.count >= 3, fields[0].tag == 0x02 else { return [] }
        // fields[1] is the community, fields[2] the PDU.
        let pdu = fields[2]
        guard pdu.tag == 0xA2 else { return [] }
        var listOffset = 0
        var pduFields: [TLV] = []
        while listOffset < pdu.body.count, let (field, next) = parseTLV(pdu.body, at: listOffset) {
            pduFields.append(field)
            listOffset = next
        }
        guard let last = pduFields.last, last.tag == 0x30 else { return [] }
        var result: [(oid: String, value: SNMPValue)] = []
        var cursor = 0
        while cursor < last.body.count,
            let (binding, next) = parseTLV(last.body, at: cursor)
        {
            cursor = next
            guard let (oidField, oidEnd) = parseTLV(binding.body, at: 0),
                oidField.tag == 0x06, oidEnd < binding.body.count,
                let (valueField, _) = parseTLV(binding.body, at: oidEnd)
            else { continue }
            result.append((decodeOID(oidField.body), value(valueField)))
        }
        return result
    }

    private static func value(_ field: TLV) -> SNMPValue {
        switch field.tag {
        case 0x02:
            let value = field.body.reduce(Int64(0)) { $0 << 8 | Int64($1) }
            return .integer(value)
        case 0x04:
            return .string(String(decoding: field.body, as: UTF8.self))
        case 0x05:
            return .null
        case 0x41:
            return .counter(field.body.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        case 0x42, 0x43:
            return .counter(field.body.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        case 0x46:
            return .counter(field.body.reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        case 0x82:
            return .endOfMibView
        default:
            return .bytes(field.body)
        }
    }
}
