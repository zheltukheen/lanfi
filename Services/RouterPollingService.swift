import Darwin
import Foundation

/// Read-only SNMP v2c GET with a strict timeout. The community string is
/// passed in memory for one request and is never written to disk or Settings.
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

    static func run(
        host: String, community: String, oids: [String], timeout: TimeInterval
    ) throws -> [String: SNMPValue] {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        guard !trimmedHost.isEmpty else { throw ClientError.invalidHost }
        guard !community.isEmpty else { throw ClientError.invalidCommunity }
        guard let address = ipv4Address(for: trimmedHost) else {
            throw ClientError.invalidHost
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw ClientError.invalidHost }
        defer { close(descriptor) }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(161).bigEndian
        destination.sin_addr = address

        let request = SNMPBER.getRequest(community: community, oids: oids)
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
        let decoded = SNMPBER.parseResponse(Array(buffer.prefix(received)))
        guard !decoded.isEmpty else { throw ClientError.malformedResponse }
        return decoded
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
