import Darwin
import Foundation
import SystemConfiguration

enum DNSClientError: Error, Equatable, LocalizedError {
    case noResolver
    case invalidResolver(String)
    case timeout
    case truncated
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .noResolver:
            return "No DNS resolver is configured."
        case .invalidResolver(let address):
            return "\(address) is not a usable IPv4 resolver."
        case .timeout:
            return "The DNS server did not answer in time."
        case .truncated:
            return "The DNS answer was truncated; try a smaller record type."
        case .socket(let detail):
            return "DNS transport failed: \(detail)"
        }
    }
}

protocol DNSLookuping: Sendable {
    func lookup(
        host: String,
        type: DNSRecordType,
        resolver: DNSResolver,
        timeout: TimeInterval
    ) async throws -> DNSLookupResult
}

struct UDPDNSClient: DNSLookuping {
    func lookup(
        host: String,
        type: DNSRecordType,
        resolver: DNSResolver,
        timeout: TimeInterval = 4
    ) async throws -> DNSLookupResult {
        let address = resolver.address ?? SystemDNSResolver.currentIPv4()
        guard let address else { throw DNSClientError.noResolver }
        guard IPv4Address(address) != nil else {
            throw DNSClientError.invalidResolver(address)
        }

        let identifier = UInt16.random(in: UInt16.min...UInt16.max)
        let query = try DNSMessage.query(name: host, type: type, id: identifier)
        let started = Date()
        let data = try await Self.exchange(query, address: address, timeout: timeout)
        let response = try DNSMessage.parseResponse(data, expecting: identifier)
        if response.truncated { throw DNSClientError.truncated }
        return DNSLookupResult(
            host: host,
            resolver: resolver.name,
            records: response.records,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000)
        )
    }

    private static func exchange(
        _ query: Data,
        address: String,
        timeout: TimeInterval
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
            guard descriptor >= 0 else {
                throw DNSClientError.socket("socket() failed")
            }
            defer { close(descriptor) }

            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = UInt16(53).bigEndian
            guard inet_pton(AF_INET, address, &destination.sin_addr) == 1 else {
                throw DNSClientError.invalidResolver(address)
            }

            let bytes = [UInt8](query)
            let sent = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        descriptor, bytes, bytes.count, 0, socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard sent == bytes.count else {
                throw DNSClientError.socket("sendto() failed")
            }

            let milliseconds = Int32(max(1, min(timeout * 1000, 60_000)))
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pollDescriptor, 1, milliseconds)
            guard ready > 0 else { throw DNSClientError.timeout }

            var buffer = [UInt8](repeating: 0, count: 65_535)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    recvfrom(
                        descriptor, &buffer, buffer.count, 0, socketAddress, &sourceLength)
                }
            }
            guard received > 0 else {
                throw DNSClientError.socket("recvfrom() failed")
            }
            return Data(buffer[0..<received])
        }.value
    }
}

enum SystemDNSResolver {
    static func currentIPv4() -> String? {
        guard
            let store = SCDynamicStoreCreate(
                nil, "LanFi.Toolkit.DNSResolver" as CFString, nil, nil),
            let raw = SCDynamicStoreCopyValue(
                store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
            let servers = raw["ServerAddresses"] as? [String]
        else { return nil }
        return servers.first { IPv4Address($0) != nil }
    }
}
