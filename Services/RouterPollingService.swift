import Darwin
import Foundation

/// Read-only SNMP v2c GET and GETNEXT with a strict timeout. The community
/// string is passed in memory for one request and is never written to disk or
/// Settings.
enum SNMPClient {
    enum ClientError: LocalizedError, Equatable {
        case invalidHost
        case invalidCommunity
        case timeout
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .invalidHost: return "Enter a router or NAS host name or address."
            case .invalidCommunity: return "Enter an SNMP community (often \"public\")."
            case .timeout: return "The device did not answer SNMP within the timeout."
            case .malformedResponse: return "The SNMP response could not be decoded."
            }
        }
    }

    static func get(
        host: String, community: String, oids: [String] = SNMPOID.standardCounters,
        timeout: TimeInterval = 2
    ) async throws -> [String: SNMPValue] {
        try await Task.detached(priority: .utility) {
            try run(host: host, community: community, oids: oids, timeout: timeout)
        }.value
    }

    /// Walks one OID subtree with GETNEXT.
    ///
    /// Stops at the end of the subtree, at an `endOfMibView`, when the agent
    /// stops advancing, or at `maxRows` — a table walk must never be able to
    /// run forever. A timeout in the middle of a table returns the rows that
    /// did arrive, but a walk that never answered throws.
    static func walk(
        host: String, community: String, root: String, maxRows: Int = 500,
        timeout: TimeInterval = 2
    ) async throws -> [(oid: String, value: SNMPValue)] {
        try await Task.detached(priority: .utility) {
            try runWalk(
                host: host, community: community, root: root, maxRows: maxRows,
                timeout: timeout)
        }.value
    }

    static func run(
        host: String, community: String, oids: [String], timeout: TimeInterval
    ) throws -> [String: SNMPValue] {
        let request = SNMPBER.getRequest(community: community, oids: oids)
        let (descriptor, destination) = try connection(host: host, community: community)
        defer { close(descriptor) }
        let bytes = try exchange(
            descriptor: descriptor, destination: destination, request: request, timeout: timeout)
        let decoded = SNMPBER.parseResponse(bytes)
        guard !decoded.isEmpty else { throw ClientError.malformedResponse }
        return decoded
    }

    static func runWalk(
        host: String, community: String, root: String, maxRows: Int, timeout: TimeInterval
    ) throws -> [(oid: String, value: SNMPValue)] {
        let (descriptor, destination) = try connection(host: host, community: community)
        defer { close(descriptor) }

        var rows: [(oid: String, value: SNMPValue)] = []
        var cursor = root
        while rows.count < max(1, maxRows) {
            let request = SNMPBER.getNextRequest(community: community, oids: [cursor])
            let bytes: [UInt8]
            do {
                bytes = try exchange(
                    descriptor: descriptor, destination: destination, request: request,
                    timeout: timeout)
            } catch {
                if rows.isEmpty { throw error }
                break
            }
            guard let binding = SNMPBER.parseVarBinds(bytes).first else { break }
            if case .endOfMibView = binding.value { break }
            // The agent answered something outside the subtree, so the table
            // ended; another request would only repeat this answer.
            guard binding.oid.hasPrefix(root + ".") else { break }
            guard binding.oid != cursor else { break }
            rows.append(binding)
            cursor = binding.oid
        }
        return rows
    }

    private static func connection(
        host: String, community: String
    ) throws -> (Int32, sockaddr_in) {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { throw ClientError.invalidHost }
        guard !community.isEmpty else { throw ClientError.invalidCommunity }
        guard let address = ipv4Address(for: trimmedHost) else {
            throw ClientError.invalidHost
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw ClientError.invalidHost }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(161).bigEndian
        destination.sin_addr = address
        return (descriptor, destination)
    }

    private static func exchange(
        descriptor: Int32, destination: sockaddr_in, request: [UInt8], timeout: TimeInterval
    ) throws -> [UInt8] {
        var destination = destination
        let sent = request.withUnsafeBytes { buffer in
            withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddr in
                    sendto(
                        descriptor, buffer.baseAddress, buffer.count, 0, sockaddr,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent == request.count else { throw ClientError.timeout }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, Int32(timeout * 1000)) > 0 else {
            throw ClientError.timeout
        }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let received = recv(descriptor, &buffer, buffer.count, 0)
        guard received > 0 else { throw ClientError.timeout }
        return Array(buffer.prefix(received))
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
}
