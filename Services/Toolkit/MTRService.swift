import Foundation

/// Repeated traceroute, merged by hop. This is an MTR-style view without a
/// second privileged engine: each round is one `traceroute -q 1` run, and the
/// per-hop loss/jitter are aggregated across rounds.
struct MTRService: Sendable {
    let runner: any TracerouteRunning

    func run(
        host: String,
        rounds: Int,
        maxHops: Int,
        waitSeconds: Int,
        onUpdate: @Sendable (MTRReport) -> Void
    ) async throws -> MTRReport {
        let startedAt = Date()
        let totalRounds = max(1, min(rounds, 100))
        var accumulators: [Int: Accumulator] = [:]
        var completed = 0

        for _ in 1...totalRounds {
            if Task.isCancelled { break }

            let report: TracerouteReport
            do {
                report = try await runner.trace(
                    host: host, maxHops: maxHops, waitSeconds: waitSeconds)
            } catch {
                if completed == 0 { throw error }
                break
            }

            let roundMax = report.hops.map(\.ttl).max() ?? 0
            if roundMax == 0 {
                completed += 1
                continue
            }
            for ttl in 1...roundMax {
                let hop = report.hops.first { $0.ttl == ttl }
                var accumulator = accumulators[ttl] ?? Accumulator()
                accumulator.sent += 1
                if let hop, let address = hop.address {
                    accumulator.received += 1
                    accumulator.address = address
                    accumulator.hostname = hop.hostname
                    if let sample = hop.averageMilliseconds {
                        accumulator.samples.append(sample)
                    }
                }
                accumulators[ttl] = accumulator
            }
            completed += 1
            onUpdate(makeReport(host: host, startedAt: startedAt, rounds: completed, accumulators: accumulators))
        }

        return makeReport(
            host: host, startedAt: startedAt, rounds: completed, accumulators: accumulators)
    }

    private func makeReport(
        host: String,
        startedAt: Date,
        rounds: Int,
        accumulators: [Int: Accumulator]
    ) -> MTRReport {
        let hops = accumulators.keys.sorted().map { ttl -> MTRHop in
            let value = accumulators[ttl] ?? Accumulator()
            let average =
                value.samples.isEmpty
                ? nil : value.samples.reduce(0, +) / Double(value.samples.count)
            return MTRHop(
                hop: ttl,
                address: value.address,
                hostname: value.hostname,
                sent: value.sent,
                received: value.received,
                lastMilliseconds: value.samples.last,
                bestMilliseconds: value.samples.min(),
                worstMilliseconds: value.samples.max(),
                averageMilliseconds: average,
                jitterMilliseconds: Self.jitter(value.samples)
            )
        }
        return MTRReport(host: host, rounds: rounds, startedAt: startedAt, hops: hops)
    }

    private static func jitter(_ samples: [Double]) -> Double? {
        guard samples.count > 1 else { return nil }
        let average = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.reduce(0) { $0 + pow($1 - average, 2) } / Double(samples.count)
        return sqrt(variance)
    }

    private struct Accumulator {
        var sent = 0
        var received = 0
        var address: String?
        var hostname: String?
        var samples: [Double] = []
    }
}
