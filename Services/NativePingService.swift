import Darwin
import Foundation

/// Sends ICMP echo requests from this process. Uses `SOCK_DGRAM` with
/// `IPPROTO_ICMP`, which macOS allows without root; no child process and no
/// raw-socket entitlement is involved.
enum NativePing {
    static func ping(
        host: String, count: Int, timeoutMilliseconds: Int = 1000,
        payloadSize: Int = 32
    ) async -> PingResult? {
        await Task.detached(priority: .utility) {
            run(
                host: host, count: count, timeoutMilliseconds: timeoutMilliseconds,
                payloadSize: payloadSize)
        }.value
    }

    /// Synchronous transport used by the detached task and the tests.
    static func run(
        host: String, count: Int, timeoutMilliseconds: Int, payloadSize: Int
    ) -> PingResult? {
        let attempts = min(max(count, 1), 20)
        guard let address = ipv4Address(for: host) else { return nil }
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }

        let identifier = UInt16(truncatingIfNeeded: getpid())
        let payload = [UInt8](repeating: 0x4C, count: max(8, min(payloadSize, 512)))
        var roundTrips: [Double] = []

        for index in 0..<attempts {
            let sequence = UInt16(truncatingIfNeeded: index)
            let packet = ICMPEcho.request(
                identifier: identifier, sequence: sequence, payload: payload)
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_addr = address
            let started = monotonicMilliseconds()

            let sent = packet.withUnsafeBytes { buffer in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                        sendto(
                            descriptor, buffer.baseAddress, buffer.count, 0, sockaddr,
                            socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent == packet.count else { continue }
            if let rtt = waitForReply(
                descriptor: descriptor, identifier: identifier, sequence: sequence,
                started: started, timeoutMilliseconds: timeoutMilliseconds)
            {
                roundTrips.append(rtt)
            }
        }

        return ICMPEcho.statistics(sent: attempts, roundTrips: roundTrips)
    }

    /// Waits for a matching echo reply until the per-packet deadline. Other
    /// datagrams (wrong identifier, stale sequence) are discarded.
    private static func waitForReply(
        descriptor: Int32, identifier: UInt16, sequence: UInt16,
        started: Double, timeoutMilliseconds: Int
    ) -> Double? {
        let deadline = started + Double(timeoutMilliseconds)
        var buffer = [UInt8](repeating: 0, count: 1500)
        while true {
            let remaining = deadline - monotonicMilliseconds()
            guard remaining > 0 else { return nil }
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, Int32(remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard ready > 0 else { return nil }
            let received = recv(descriptor, &buffer, buffer.count, 0)
            guard received > 0 else { continue }
            guard let reply = ICMPEcho.parseReply(Array(buffer.prefix(received))),
                reply.identifier == identifier, reply.sequence == sequence
            else { continue }
            return monotonicMilliseconds() - started
        }
    }

    private static func ipv4Address(for host: String) -> in_addr? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return nil
        }
        defer { freeaddrinfo(first) }
        guard let address = first.pointee.ai_addr else { return nil }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
    }

    private static func monotonicMilliseconds() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000
    }
}
