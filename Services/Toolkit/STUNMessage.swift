import Foundation

/// The parts of RFC 5389 this app needs: a binding request and the mapped
/// address from the answer. Nothing else is decoded, because nothing else
/// changes the verdict.
enum STUNMessage {
    static let magicCookie: UInt32 = 0x2112_A442
    static let bindingRequestType: UInt16 = 0x0001
    static let bindingSuccessType: UInt16 = 0x0101

    private static let attributeMappedAddress: UInt16 = 0x0001
    private static let attributeXORMappedAddress: UInt16 = 0x0020

    static func bindingRequest(transactionID: [UInt8]) -> Data {
        precondition(transactionID.count == 12)
        var data = Data()
        data.append(contentsOf: [UInt8(bindingRequestType >> 8), UInt8(bindingRequestType & 0xFF)])
        data.append(contentsOf: [0, 0])  // length: no attributes
        data.append(contentsOf: withUnsafeBytes(of: magicCookie.bigEndian, Array.init))
        data.append(contentsOf: transactionID)
        return data
    }

    static func randomTransactionID() -> [UInt8] {
        (0..<12).map { _ in UInt8.random(in: 0...255) }
    }

    /// Returns the mapped endpoint of a binding success response, handling
    /// both XOR-MAPPED-ADDRESS (what every current server sends) and the
    /// deprecated MAPPED-ADDRESS.
    static func mappedEndpoint(from data: Data) -> STUNEndpoint? {
        guard data.count >= 20 else { return nil }
        let bytes = [UInt8](data)
        let type = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        guard type == bindingSuccessType else { return nil }
        let length = Int(UInt16(bytes[2]) << 8 | UInt16(bytes[3]))
        guard 20 + length <= bytes.count else { return nil }

        var offset = 20
        while offset + 4 <= 20 + length {
            let attribute = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            let attributeLength = Int(UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3]))
            let valueStart = offset + 4
            guard valueStart + attributeLength <= bytes.count else { return nil }
            if attribute == attributeXORMappedAddress, attributeLength >= 8 {
                return endpoint(
                    family: bytes[valueStart + 1],
                    port: UInt16(bytes[valueStart + 2]) << 8 | UInt16(bytes[valueStart + 3]),
                    address: Array(bytes[(valueStart + 4)..<(valueStart + attributeLength)]),
                    xorPort: 0x2112,
                    xorAddress: Array(bytes[4..<8]))
            }
            if attribute == attributeMappedAddress, attributeLength >= 8 {
                return endpoint(
                    family: bytes[valueStart + 1],
                    port: UInt16(bytes[valueStart + 2]) << 8 | UInt16(bytes[valueStart + 3]),
                    address: Array(bytes[(valueStart + 4)..<(valueStart + attributeLength)]),
                    xorPort: 0,
                    xorAddress: nil)
            }
            // Attributes are padded to a 4-byte boundary.
            offset = valueStart + ((attributeLength + 3) / 4) * 4
        }
        return nil
    }

    private static func endpoint(
        family: UInt8, port: UInt16, address: [UInt8], xorPort: UInt16, xorAddress: [UInt8]?
    ) -> STUNEndpoint? {
        let resolvedPort = port ^ xorPort
        switch family {
        case 0x01 where address.count >= 4:
            var octets = Array(address.prefix(4))
            if let xorAddress {
                for index in 0..<4 { octets[index] ^= xorAddress[index] }
            }
            return STUNEndpoint(
                address: octets.map(String.init).joined(separator: "."), port: resolvedPort)
        case 0x02 where address.count >= 16:
            var octets = Array(address.prefix(16))
            if let xorAddress {
                let mask = xorAddress + [UInt8](repeating: 0, count: 12)
                for index in 0..<16 { octets[index] ^= mask[index] }
            }
            let groups = stride(from: 0, to: 16, by: 2).map { index in
                String(format: "%02x%02x", octets[index], octets[index + 1])
            }
            return STUNEndpoint(address: groups.joined(separator: ":"), port: resolvedPort)
        default:
            return nil
        }
    }
}
