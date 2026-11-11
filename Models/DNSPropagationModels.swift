import Foundation

struct DNSPropagationResult: Identifiable, Equatable, Sendable {
    let resolver: DNSResolver
    let records: [DNSRecord]
    let milliseconds: Int
    let error: String?

    var id: String { resolver.id }

    var values: [String] { records.map(\.value) }

    var isSuccess: Bool { error == nil }
}

struct DNSPropagationSummary: Equatable, Sendable {
    let expected: String
    let results: [DNSPropagationResult]

    var successfulCount: Int { results.filter(\.isSuccess).count }
    var matchingCount: Int {
        guard !expected.isEmpty else { return 0 }
        return results.filter { result in
            result.isSuccess && result.values.contains { $0.caseInsensitiveCompare(expected) == .orderedSame }
        }.count
    }
    var allMatch: Bool {
        !expected.isEmpty && !results.isEmpty && matchingCount == results.count
    }
    var consistent: Bool {
        guard let first = results.first(where: \.isSuccess)?.values.sorted() else { return false }
        return results.filter(\.isSuccess).allSatisfy { $0.values.sorted() == first }
    }
}

extension DNSResolver {
    static let propagation: [DNSResolver] = [
        .cloudflare,
        .google,
        DNSResolver(id: "quad9", name: "Quad9", address: "9.9.9.9"),
        DNSResolver(id: "opendns", name: "OpenDNS", address: "208.67.222.222"),
        DNSResolver(id: "level3", name: "Level3", address: "4.2.2.1"),
        DNSResolver(id: "cloudflare-alt", name: "Cloudflare 2", address: "1.0.0.1"),
    ]
}
