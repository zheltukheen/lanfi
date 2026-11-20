import Foundation
import Network

/// Adds country and network data to the addresses a DNS answer points at.
///
/// Only A and AAAA records are annotated, the addresses are deduplicated, and
/// at most `limit` lookups run per answer: a CDN name can return a dozen
/// addresses and a third-party lookup per address would be rude to the service
/// and slow for the user. A failed lookup simply leaves the cell empty.
struct DNSAddressEnricher: Sendable {
    var lookup: @Sendable (String) async throws -> GeoIPReport = { address in
        try await GeoIPClient().lookup(address)
    }
    var limit = 4

    func annotations(for records: [DNSRecord]) async -> [String: DNSAddressAnnotation] {
        var seen = Set<String>()
        var addresses: [String] = []
        for record in records where record.type == .a || record.type == .aaaa {
            let value = record.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, IPv4Address(value) != nil || IPv6Address(value) != nil else {
                continue
            }
            if seen.insert(value).inserted { addresses.append(value) }
            if addresses.count == limit { break }
        }
        guard !addresses.isEmpty else { return [:] }

        let lookup = self.lookup
        return await withTaskGroup(of: (String, DNSAddressAnnotation?).self) { group in
            for address in addresses {
                group.addTask {
                    guard let report = try? await lookup(address) else { return (address, nil) }
                    return (address, DNSAddressAnnotation(report: report))
                }
            }
            var result: [String: DNSAddressAnnotation] = [:]
            for await (address, annotation) in group {
                if let annotation { result[address] = annotation }
            }
            return result
        }
    }
}
