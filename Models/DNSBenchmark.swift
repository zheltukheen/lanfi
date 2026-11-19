import Foundation

/// A resolver the benchmark measures. The system resolver has no address: the
/// client reads whatever the Mac is using right now.
struct DNSBenchmarkResolver: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let resolver: DNSResolver

    static let system = DNSBenchmarkResolver(
        id: "system", name: "System", resolver: .system)
    static let cloudflare = DNSBenchmarkResolver(
        id: "cloudflare", name: "Cloudflare 1.1.1.1", resolver: .cloudflare)
    static let google = DNSBenchmarkResolver(
        id: "google", name: "Google 8.8.8.8", resolver: .google)
    static let quad9 = DNSBenchmarkResolver(
        id: "quad9", name: "Quad9 9.9.9.9",
        resolver: DNSResolver(id: "quad9", name: "Quad9", address: "9.9.9.9"))

    /// Never a preset for switching — this list only drives the measurement.
    static let defaults: [DNSBenchmarkResolver] = [.system, .cloudflare, .google, .quad9]
}

/// One row of the benchmark table.
struct DNSBenchmarkResult: Identifiable, Equatable, Sendable {
    let resolverID: String
    let name: String
    let samples: [Double]
    let failures: Int

    var id: String { resolverID }

    var medianMilliseconds: Double? {
        DNSBenchmarkRanker.median(samples)
    }

    var fastestMilliseconds: Double? { samples.min() }
    var slowestMilliseconds: Double? { samples.max() }
    var lookupCount: Int { samples.count + failures }
}

struct DNSBenchmarkReport: Equatable, Sendable {
    let startedAt: Date
    let results: [DNSBenchmarkResult]

    var ranked: [DNSBenchmarkResult] { DNSBenchmarkRanker.ranked(results) }

    /// The fastest resolver that answered everything, if there is one. The UI
    /// only ever recommends; it never switches the system resolver by itself.
    var fastest: DNSBenchmarkResult? {
        ranked.first { $0.medianMilliseconds != nil && $0.failures == 0 }
    }
}

enum DNSBenchmarkRanker {
    /// Median of the successful lookups. A median ignores the one slow outlier
    /// a resolver hits when its cache is cold.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Answered resolvers first, fastest median first, then fewest failures.
    static func ranked(_ results: [DNSBenchmarkResult]) -> [DNSBenchmarkResult] {
        results.sorted { lhs, rhs in
            switch (lhs.medianMilliseconds, rhs.medianMilliseconds) {
            case let (left?, right?):
                if left != right { return left < right }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            if lhs.failures != rhs.failures { return lhs.failures < rhs.failures }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
