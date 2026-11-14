import Darwin
import Foundation

enum WakeOnLANError: LocalizedError, Equatable {
    case invalidMAC
    case socket(String)
    case send(String)

    var errorDescription: String? {
        switch self {
        case .invalidMAC: return String(localized: "This device has no usable MAC address.")
        case .socket(let detail): return String(localized: "Could not open a socket: \(detail)")
        case .send(let detail): return detail
        }
    }
}

/// Wake-on-LAN magic packets, sent straight from the LAN Scanner. The device
/// only needs to have WoL enabled in its firmware and be reachable on the same
/// broadcast domain.
enum WakeOnLAN {
    static let defaultPort: UInt16 = 9

    static func magicPacket(mac: String) -> Data? {
        let hex = mac.filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    static func send(
        mac: String, broadcast: String = "255.255.255.255", port: UInt16 = defaultPort
    ) throws {
        guard let packet = magicPacket(mac: mac) else { throw WakeOnLANError.invalidMAC }
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else {
            throw WakeOnLANError.socket(String(cString: strerror(errno)))
        }
        defer { close(descriptor) }

        var enabled: Int32 = 1
        setsockopt(
            descriptor, SOL_SOCKET, SO_BROADCAST, &enabled,
            socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, broadcast, &address.sin_addr) == 1 else {
            throw WakeOnLANError.send(String(localized: "\(broadcast) is not a valid broadcast address."))
        }

        let sent = packet.withUnsafeBytes { raw -> Int in
            withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(
                        descriptor, raw.baseAddress, packet.count, 0, sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == packet.count else {
            throw WakeOnLANError.send(String(cString: strerror(errno)))
        }
    }
}
