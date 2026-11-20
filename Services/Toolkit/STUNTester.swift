import Darwin
import Foundation

enum STUNError: LocalizedError {
    case invalidServer
    case resolveFailed(String)
    case timeout
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Enter a STUN server as host:port."
        case .resolveFailed(let host): return "\(host) did not resolve to an IPv4 address."
        case .timeout: return "The STUN server did not answer."
        case .socket(let detail): return "STUN transport failed: \(detail)"
        }
    }
}

extension STUNEndpoint {
    /// The public servers this build talks to by default. Documented here so
    /// the list is visible in one place instead of hidden in a text field.
    static let builtIn: [STUNEndpoint] = [
        STUNEndpoint(address: "stun.l.google.com", port: 19302),
        STUNEndpoint(address: "stun.cloudflare.com", port: 3478),
    ]

    static func parse(_ text: String) -> STUNEndpoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), port > 0 else { return nil }
        let host = String(parts[0])
        guard !host.isEmpty, !host.hasPrefix("-") else { return nil }
        return STUNEndpoint(address: host, port: port)
    }
}

/// Sends binding requests from one UDP socket to two servers.
///
/// One socket is the whole point: the router's mapping can only be compared
/// when every probe leaves from the same source port. Filtering behaviour
/// needs a server that sends back to the mapped address, which public STUN
/// servers do not do on request, so it stays unprobed rather than guessed.
struct STUNTester: Sendable {
    var servers: [STUNEndpoint] = STUNEndpoint.builtIn
    var timeout: TimeInterval = 3

    func run() async -> NATReport {
        await Task.detached(priority: .userInitiated) { session() }.value
    }

    private func session() -> NATReport {
        let servers = Array(self.servers.prefix(2))
        guard let first = servers.first else {
            return NATReport(
                localEndpoint: STUNEndpoint(address: "—", port: 0), probes: [],
                mapping: .unknown, filtering: .unknown)
        }
        guard let resolved = Self.resolve(first) else {
            return NATReport(
                localEndpoint: STUNEndpoint(address: "—", port: 0),
                probes: [
                    NATProbe(
                        id: "0", server: first, mapped: nil, milliseconds: nil,
                        failure: STUNError.resolveFailed(first.address).localizedDescription)
                ],
                mapping: .unknown, filtering: .unknown)
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else {
            return emptyReport(first, message: STUNError.socket("socket() failed").localizedDescription)
        }
        defer { close(descriptor) }

        var local = sockaddr_in()
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                bind(descriptor, address, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            return emptyReport(first, message: STUNError.socket("bind() failed").localizedDescription)
        }
        let localPort = Self.port(of: descriptor) ?? 0
        let localAddress = Self.localAddress(towards: resolved) ?? "—"

        // Two probes to the first server prove the mapping is stable, the third
        // to a different server proves whether the router reuses it.
        var probes: [NATProbe] = []
        let plan: [(server: STUNEndpoint, address: sockaddr_in)] = {
            var result: [(STUNEndpoint, sockaddr_in)] = [(first, resolved), (first, resolved)]
            if servers.count > 1, let second = Self.resolve(servers[1]) {
                result.append((servers[1], second))
            }
            return result
        }()

        for (index, step) in plan.enumerated() {
            let transactionID = STUNMessage.randomTransactionID()
            let query = STUNMessage.bindingRequest(transactionID: transactionID)
            let started = Date()
            do {
                try Self.send(query, to: step.address, on: descriptor)
                let answer = try Self.receive(on: descriptor, timeout: timeout)
                guard
                    answer.count >= 20,
                    Array(answer[8..<20]) == transactionID,
                    let mapped = STUNMessage.mappedEndpoint(from: answer)
                else {
                    throw STUNError.timeout
                }
                probes.append(
                    NATProbe(
                        id: "\(index)", server: step.server, mapped: mapped,
                        milliseconds: Int(Date().timeIntervalSince(started) * 1000), failure: nil))
            } catch {
                probes.append(
                    NATProbe(
                        id: "\(index)", server: step.server, mapped: nil, milliseconds: nil,
                        failure: error.localizedDescription))
            }
        }

        return NATReport(
            localEndpoint: STUNEndpoint(address: localAddress, port: localPort),
            probes: probes,
            mapping: NATReport.mapping(for: probes),
            filtering: .unknown)
    }

    private func emptyReport(_ server: STUNEndpoint, message: String) -> NATReport {
        NATReport(
            localEndpoint: STUNEndpoint(address: "—", port: 0),
            probes: [NATProbe(id: "0", server: server, mapped: nil, milliseconds: nil, failure: message)],
            mapping: .unknown, filtering: .unknown)
    }

    // MARK: - Sockets

    private static func resolve(_ endpoint: STUNEndpoint) -> sockaddr_in? {
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: IPPROTO_UDP,
            ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard
            getaddrinfo(endpoint.address, String(endpoint.port), &hints, &result) == 0,
            let first = result
        else { return nil }
        defer { freeaddrinfo(first) }
        guard let address = first.pointee.ai_addr else { return nil }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    private static func send(_ data: Data, to address: sockaddr_in, on descriptor: Int32) throws {
        var destination = address
        let bytes = [UInt8](data)
        let sent = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                sendto(
                    descriptor, bytes, bytes.count, 0, socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == bytes.count else { throw STUNError.socket("sendto() failed") }
    }

    private static func receive(on descriptor: Int32, timeout: TimeInterval) throws -> Data {
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let ready = poll(&pollDescriptor, 1, Int32(max(1, timeout * 1000)))
        guard ready > 0 else { throw STUNError.timeout }
        var buffer = [UInt8](repeating: 0, count: 1500)
        var source = sockaddr_in()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let received = withUnsafeMutablePointer(to: &source) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                recvfrom(descriptor, &buffer, buffer.count, 0, socketAddress, &sourceLength)
            }
        }
        guard received > 0 else { throw STUNError.socket("recvfrom() failed") }
        return Data(buffer[0..<received])
    }

    private static func port(of descriptor: Int32) -> UInt16? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard result == 0 else { return nil }
        return UInt16(bigEndian: address.sin_port)
    }

    /// The address this Mac would use to reach the server, so "no NAT" can be
    /// told apart from a router that rewrites the address.
    private static func localAddress(towards address: sockaddr_in) -> String? {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var destination = address
        let connected = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard result == 0 else { return nil }
        var copy = local.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &copy, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            return nil
        }
        return String(cString: buffer)
    }
}
