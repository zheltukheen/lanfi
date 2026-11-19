import Foundation

/// Measures how long the same set of names takes to resolve through several
/// resolvers. Read-only: it never changes the system DNS setting.
struct DNSBenchmarkService: Sendable {
    var client: any DNSLookuping = UDPDNSClient()
    /// A short fixed list keeps the whole run under a few seconds while still
    /// touching a cache miss (three different TLDs).
    var hosts: [String] = ["apple.com", "cloudflare.com", "wikipedia.org"]
    var rounds = 3
    var timeout: TimeInterval = 2

    func run(
        resolvers: [DNSBenchmarkResolver],
        onResult: @Sendable (DNSBenchmarkResult) -> Void = { _ in }
    ) async -> DNSBenchmarkReport {
        let startedAt = Date()
        var results: [DNSBenchmarkResult] = []
        for resolver in resolvers {
            if Task.isCancelled { break }
            var samples: [Double] = []
            var failures = 0
            for _ in 0..<max(1, rounds) {
                for host in hosts {
                    if Task.isCancelled { break }
                    do {
                        let result = try await client.lookup(
                            host: host, type: .a, resolver: resolver.resolver,
                            timeout: timeout)
                        samples.append(Double(result.milliseconds))
                    } catch {
                        failures += 1
                    }
                }
            }
            let row = DNSBenchmarkResult(
                resolverID: resolver.id, name: resolver.name,
                samples: samples, failures: failures)
            results.append(row)
            onResult(row)
        }
        return DNSBenchmarkReport(startedAt: startedAt, results: results)
    }
}
