import Foundation

/// P2 — ICMP echo without spawning `/sbin/ping`. macOS may withdraw Local
/// Network access from child processes, so the diagnostics transport builds
/// and parses the echo itself on an unprivileged datagram ICMP socket.
enum ICMPEcho {
    static let echoRequestType: UInt8 = 8
    static let echoReplyType: UInt8 = 0

    /// 8-byte ICMP header plus payload, checksum filled in.
    static func request(identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [
            echoRequestType, 0, 0, 0,
            UInt8(identifier >> 8), UInt8(identifier & 0xFF),
            UInt8(sequence >> 8), UInt8(sequence & 0xFF),
        ]
        bytes.append(contentsOf: payload)
        let sum = checksum(bytes)
        bytes[2] = UInt8(sum >> 8)
        bytes[3] = UInt8(sum & 0xFF)
        return bytes
    }

    /// RFC 1071 one's-complement sum over 16-bit words.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum &+= UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum &+= UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return UInt16(~sum & 0xFFFF)
    }

    struct Reply: Equatable {
        let type: UInt8
        let identifier: UInt16
        let sequence: UInt16
    }

    /// Reads the ICMP header of a received datagram. The kernel strips the IP
    /// header for datagram ICMP sockets, so byte 0 is the ICMP type.
    static func parseReply(_ bytes: [UInt8]) -> Reply? {
        guard bytes.count >= 8, bytes[0] == echoReplyType else { return nil }
        return Reply(
            type: bytes[0],
            identifier: UInt16(bytes[4]) << 8 | UInt16(bytes[5]),
            sequence: UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        )
    }

    /// RTT statistics for the replies that matched our identifier and sequence.
    static func statistics(sent: Int, roundTrips: [Double]) -> PingResult? {
        guard sent > 0 else { return nil }
        let received = roundTrips.count
        let average = received > 0 ? roundTrips.reduce(0, +) / Double(received) : nil
        let deviation: Double? = average.map { mean in
            let variance = roundTrips.reduce(0) { $0 + pow($1 - mean, 2) } / Double(received)
            return sqrt(variance)
        }
        return PingResult(
            transmitted: sent,
            received: received,
            packetLossPercent: Double(sent - received) / Double(sent) * 100,
            minMilliseconds: roundTrips.min(),
            averageMilliseconds: average,
            maxMilliseconds: roundTrips.max(),
            standardDeviationMilliseconds: deviation
        )
    }
}
