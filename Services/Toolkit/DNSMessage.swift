import Darwin
import Foundation

enum DNSMessageError: Error, Equatable {
    case invalidName(String)
    case truncated
    case malformed(String)
    case serverFailure(Int)
    case identifierMismatch
}

struct DNSResponse: Equatable, Sendable {
    let records: [DNSRecord]
    let truncated: Bool
    let responseCode: Int
}

enum DNSMessage {

    // MARK: - Query

    static func query(name: String, type: DNSRecordType, id: UInt16) throws -> Data {
        let labels = try encodeLabels(name)
        var writer = ByteWriter()
        writer.u16(id)
        writer.u16(0x0100) // recursion desired
        writer.u16(1) // QDCOUNT
        writer.u16(0) // ANCOUNT
        writer.u16(0) // NSCOUNT
        writer.u16(0) // ARCOUNT
        for label in labels {
            writer.u8(UInt8(label.count))
            writer.bytes(label)
        }
        writer.u8(0)
        writer.u16(type.rawValue)
        writer.u16(1) // IN
        return writer.data
    }

    private static func encodeLabels(_ name: String) throws -> [[UInt8]] {
        var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasSuffix(".") { normalized.removeLast() }
        guard !normalized.isEmpty, normalized.unicodeScalars.allSatisfy(\.isASCII) else {
            throw DNSMessageError.invalidName(name)
        }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        var total = 0
        var labels: [[UInt8]] = []
        for part in parts {
            let bytes = Array(part.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else {
                throw DNSMessageError.invalidName(name)
            }
            total += bytes.count + 1
            guard total <= 253 else { throw DNSMessageError.invalidName(name) }
            labels.append(bytes)
        }
        return labels
    }

    // MARK: - Response

    static func parseResponse(_ data: Data, expecting id: UInt16? = nil) throws -> DNSResponse {
        var reader = ByteReader(data: data)
        guard data.count >= 12 else { throw DNSMessageError.truncated }

        let identifier = try reader.u16()
        if let id, id != identifier { throw DNSMessageError.identifierMismatch }
        let flags = try reader.u16()
        let questionCount = Int(try reader.u16())
        let answerCount = Int(try reader.u16())
        _ = try reader.u16()
        _ = try reader.u16()

        let truncated = flags & 0x0200 != 0
        let responseCode = Int(flags & 0x000F)
        guard responseCode == 0 else { throw DNSMessageError.serverFailure(responseCode) }

        for _ in 0..<questionCount {
            _ = try reader.readName()
            _ = try reader.u16()
            _ = try reader.u16()
        }

        var records: [DNSRecord] = []
        for _ in 0..<answerCount {
            let name = try reader.readName()
            let rawType = try reader.u16()
            let recordClass = try reader.u16()
            let ttl = try reader.u32()
            let length = Int(try reader.u16())
            let start = reader.offset
            let end = start + length
            guard end <= data.count else { throw DNSMessageError.truncated }

            if recordClass == 1, let type = DNSRecordType(rawValue: rawType) {
                if let record = try decodeRecord(
                    type: type, name: name, ttl: ttl, reader: &reader, end: end
                ) {
                    records.append(record)
                }
            }
            reader.offset = end
        }
        return DNSResponse(records: records, truncated: truncated, responseCode: responseCode)
    }

    private static func decodeRecord(
        type: DNSRecordType,
        name: String,
        ttl: UInt32,
        reader: inout ByteReader,
        end: Int
    ) throws -> DNSRecord? {
        var priority: UInt16?
        let value: String

        switch type {
        case .a:
            guard end - reader.offset >= 4 else { throw DNSMessageError.malformed("short A record") }
            let bytes = try reader.bytes(count: 4)
            value = bytes.map(String.init).joined(separator: ".")
        case .aaaa:
            guard end - reader.offset >= 16 else {
                throw DNSMessageError.malformed("short AAAA record")
            }
            value = formatIPv6(try reader.bytes(count: 16))
        case .cname, .ns, .ptr:
            value = try reader.readName()
        case .mx:
            guard end - reader.offset >= 2 else { throw DNSMessageError.malformed("short MX record") }
            priority = try reader.u16()
            value = try reader.readName()
        case .txt:
            var pieces: [String] = []
            while reader.offset < end {
                guard reader.offset + 1 <= end else { throw DNSMessageError.malformed("short TXT") }
                let length = Int(try reader.u8())
                guard reader.offset + length <= end else {
                    throw DNSMessageError.malformed("TXT segment out of range")
                }
                pieces.append(String(decoding: try reader.bytes(count: length), as: UTF8.self))
            }
            value = pieces.joined(separator: " ")
        case .soa:
            let primary = try reader.readName()
            let mailbox = try reader.readName()
            let serial = try reader.u32()
            let refresh = try reader.u32()
            let retry = try reader.u32()
            let expire = try reader.u32()
            let minimum = try reader.u32()
            value =
                "\(primary) \(mailbox) \(serial) \(refresh) \(retry) \(expire) \(minimum)"
        case .srv:
            guard end - reader.offset >= 6 else { throw DNSMessageError.malformed("short SRV") }
            priority = try reader.u16()
            _ = try reader.u16()
            let port = try reader.u16()
            let target = try reader.readName()
            value = "\(target):\(port)"
        case .caa:
            guard end - reader.offset >= 2 else { throw DNSMessageError.malformed("short CAA") }
            let flags = try reader.u8()
            let tagLength = Int(try reader.u8())
            guard reader.offset + tagLength <= end else {
                throw DNSMessageError.malformed("CAA tag out of range")
            }
            let tag = String(decoding: try reader.bytes(count: tagLength), as: UTF8.self)
            let remainder = try reader.bytes(count: end - reader.offset)
            value = "\(flags) \(tag) \"\(String(decoding: remainder, as: UTF8.self))\""
        }

        return DNSRecord(name: name, type: type, ttl: ttl, priority: priority, value: value)
    }

    private static func formatIPv6(_ bytes: [UInt8]) -> String {
        guard bytes.count == 16 else { return bytes.map(String.init).joined(separator: ":") }
        var address = in6_addr()
        withUnsafeMutableBytes(of: &address) { buffer in
            buffer.copyBytes(from: bytes)
        }
        var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &output, socklen_t(output.count)) != nil else {
            return bytes.map(String.init).joined(separator: ":")
        }
        return String(cString: output)
    }
}

// MARK: - Wire helpers

private struct ByteWriter {
    var data = Data()

    mutating func u8(_ value: UInt8) {
        data.append(value)
    }

    mutating func u16(_ value: UInt16) {
        data.append(UInt8(value >> 8))
        data.append(UInt8(value & 0xff))
    }

    mutating func u32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    mutating func bytes(_ value: [UInt8]) {
        data.append(contentsOf: value)
    }
}

private struct ByteReader {
    let data: Data
    var offset: Int = 0

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw DNSMessageError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u16() throws -> UInt16 {
        guard offset + 2 <= data.count else { throw DNSMessageError.truncated }
        let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        offset += 2
        return value
    }

    mutating func u32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw DNSMessageError.truncated }
        let value =
            UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
        offset += 4
        return value
    }

    mutating func bytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw DNSMessageError.truncated }
        defer { offset += count }
        return Array(data[offset..<(offset + count)])
    }

    mutating func readName() throws -> String {
        var labels: [String] = []
        var position = offset
        var jumped = false
        var jumps = 0

        while true {
            guard position < data.count else { throw DNSMessageError.truncated }
            let length = Int(data[position])
            if length == 0 {
                position += 1
                if !jumped { offset = position }
                break
            }
            if length & 0xC0 == 0xC0 {
                guard position + 1 < data.count else { throw DNSMessageError.truncated }
                let pointer = (length & 0x3F) << 8 | Int(data[position + 1])
                guard pointer < data.count else {
                    throw DNSMessageError.malformed("name pointer out of range")
                }
                if !jumped {
                    offset = position + 2
                    jumped = true
                }
                position = pointer
                jumps += 1
                guard jumps <= 64 else { throw DNSMessageError.malformed("name pointer loop") }
                continue
            }
            guard length > 0, position + 1 + length <= data.count else {
                throw DNSMessageError.malformed("label out of range")
            }
            let start = position + 1
            let end = start + length
            labels.append(String(decoding: data[start..<end], as: UTF8.self))
            position = end
        }
        return labels.joined(separator: ".")
    }
}
