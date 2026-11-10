import Darwin
import Foundation
import Network

// MARK: - Ping

protocol PingProbing: Sendable {
    func probe(host: String, sequence: Int, timeout: TimeInterval) async -> PingSample
}

struct PingService: Sendable {
    let probe: PingProbing

    func run(
        host: String,
        count: Int,
        interval: TimeInterval,
        timeout: TimeInterval = 1.5
    ) async -> PingStatistics {
        var samples: [PingSample] = []
        for await sample in stream(
            host: host, count: count, interval: interval, timeout: timeout)
        {
            samples.append(sample)
        }
        return PingStatistics(host: host, samples: samples)
    }

    /// Yields each reply as it arrives so the UI can draw a live chart.
    func stream(
        host: String,
        count: Int,
        interval: TimeInterval,
        timeout: TimeInterval = 1.5
    ) -> AsyncStream<PingSample> {
        let total = max(1, min(count, 10_000))
        let probe = probe
        return AsyncStream { continuation in
            let task = Task {
                for sequence in 1...total {
                    if Task.isCancelled { break }
                    let sample = await probe.probe(
                        host: host, sequence: sequence, timeout: timeout)
                    continuation.yield(sample)
                    if sequence < total, interval > 0 {
                        do {
                            try await Task.sleep(
                                nanoseconds: UInt64(interval * 1_000_000_000))
                        } catch {
                            break
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - ICMP

/// Unprivileged ICMP echo using `SOCK_DGRAM`/`IPPROTO_ICMP`.
///
/// macOS returns the IPv4 header in front of the ICMP message on this socket
/// type, so replies are parsed after the IHL offset. The kernel rewrites the
/// identifier, so only the sequence number is matched.
struct ICMPPingProbe: PingProbing {
    func probe(host: String, sequence: Int, timeout: TimeInterval) async -> PingSample {
        await Task.detached(priority: .utility) {
            Self.perform(host: host, sequence: sequence, timeout: timeout)
        }.value
    }

    private static func perform(host: String, sequence: Int, timeout: TimeInterval) -> PingSample {
        guard let address = resolveIPv4(host) else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Could not resolve host")
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Could not open ICMP socket")
        }
        defer { close(descriptor) }

        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8  // echo request
        packet[1] = 0
        let identifier = UInt16(getpid() & 0xffff)
        let sequenceNumber = UInt16(sequence & 0xffff)
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xff)
        packet[6] = UInt8(sequenceNumber >> 8)
        packet[7] = UInt8(sequenceNumber & 0xff)
        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xff)

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = 0
        guard inet_pton(AF_INET, address, &destination.sin_addr) == 1 else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Invalid IPv4 address")
        }

        let started = DispatchTime.now()
        let sent = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                sendto(
                    descriptor, packet, packet.count, 0, socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == packet.count else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "ICMP send failed")
        }

        let timeoutMilliseconds = Int32(max(1, min(timeout * 1000, 60_000)))
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollDescriptor, 1, timeoutMilliseconds)
        guard ready > 0 else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil,
                error: ready == 0 ? "Timed out" : "ICMP wait failed")
        }

        var buffer = [UInt8](repeating: 0, count: 1500)
        var source = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                recvfrom(
                    descriptor, &buffer, buffer.count, 0, socketAddress, &sourceLength)
            }
        }
        guard received >= 28 else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Short ICMP reply")
        }

        let headerLength = Int(buffer[0] & 0x0f) * 4
        guard headerLength >= 20, received >= headerLength + 8 else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Malformed ICMP reply")
        }
        let type = buffer[headerLength]
        let code = buffer[headerLength + 1]
        let replySequence =
            UInt16(buffer[headerLength + 6]) << 8 | UInt16(buffer[headerLength + 7])
        guard type == 0, code == 0, replySequence == sequenceNumber else {
            return PingSample(
                sequence: sequence, rttMilliseconds: nil, error: "Unexpected ICMP reply")
        }

        let elapsed =
            Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds)
            / 1_000_000
        return PingSample(sequence: sequence, rttMilliseconds: elapsed)
    }

    private static func resolveIPv4(_ host: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = 0

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return nil
        }
        defer { freeaddrinfo(first) }

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard
            getnameinfo(
                first.pointee.ai_addr, first.pointee.ai_addrlen, &buffer,
                socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(cString: buffer)
    }

    private static func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count {
            sum += UInt32(bytes[index]) << 8
        }
        while sum >> 16 != 0 {
            sum = (sum & 0xffff) + (sum >> 16)
        }
        return UInt16(~sum & 0xffff)
    }
}

// MARK: - TCP connect probe

enum TCPProbeOutcome: Equatable, Sendable {
    case open(milliseconds: Double)
    case closed(milliseconds: Double?, detail: String?)
    case filtered(detail: String?)

    var state: PortState {
        switch self {
        case .open: return .open
        case .closed: return .closed
        case .filtered: return .filtered
        }
    }
}

enum TCPProbe {
    static func connect(host: String, port: UInt16, timeout: TimeInterval) async -> TCPProbeOutcome {
        guard let networkPort = NWEndpoint.Port(rawValue: port) else {
            return .filtered(detail: "Invalid port")
        }

        return await withCheckedContinuation {
            (continuation: CheckedContinuation<TCPProbeOutcome, Never>) in
            let queue = DispatchQueue(label: "ru.zheltukheen.LanFi.tcp-probe")
            let connection = NWConnection(
                host: NWEndpoint.Host(host), port: networkPort, using: .tcp)
            let once = OnceFlag()
            let started = DispatchTime.now()

            let finish: @Sendable (TCPProbeOutcome) -> Void = { outcome in
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: outcome)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.open(milliseconds: elapsedMilliseconds(since: started)))
                case .failed(let error):
                    finish(classify(error, started: started))
                case .waiting:
                    // Keep waiting until the timeout fires.
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.filtered(detail: String(format: "No response within %.1f s", timeout)))
            }
        }
    }

    private static func classify(_ error: NWError, started: DispatchTime) -> TCPProbeOutcome {
        let elapsed = elapsedMilliseconds(since: started)
        switch error {
        case .posix(let code) where code == .ECONNREFUSED:
            return .closed(milliseconds: elapsed, detail: "Connection refused")
        case .posix(let code) where code == .ETIMEDOUT:
            return .filtered(detail: "Timed out")
        default:
            return .filtered(detail: error.localizedDescription)
        }
    }

    private static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

struct TCPPingProbe: PingProbing {
    let port: UInt16

    func probe(host: String, sequence: Int, timeout: TimeInterval) async -> PingSample {
        switch await TCPProbe.connect(host: host, port: port, timeout: timeout) {
        case .open(let milliseconds):
            return PingSample(sequence: sequence, rttMilliseconds: milliseconds)
        case .closed(_, let detail):
            return PingSample(sequence: sequence, rttMilliseconds: nil, error: detail ?? "Refused")
        case .filtered(let detail):
            return PingSample(sequence: sequence, rttMilliseconds: nil, error: detail ?? "No reply")
        }
    }
}
