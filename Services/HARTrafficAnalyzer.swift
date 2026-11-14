import Foundation

struct HARHostSummary: Identifiable, Equatable {
    let host: String
    let requests: Int
    let failures: Int
    let bytes: Int
    let averageMilliseconds: Double
    let slowestMilliseconds: Double

    var id: String { host }
}

struct HARStatusBucket: Identifiable, Equatable {
    let code: Int
    let count: Int

    var id: Int { code }
}

struct HARPhaseAverage: Identifiable, Equatable {
    let name: String
    let milliseconds: Double

    var id: String { name }
}

struct HARInsights: Equatable {
    let requestCount: Int
    let failureCount: Int
    let redirectCount: Int
    let cachedCount: Int
    let transferBytes: Int
    let contentBytes: Int
    let averageMilliseconds: Double
    let p95Milliseconds: Double
    let slowestMilliseconds: Double
    let slowest: [HAREntry]
    let hosts: [HARHostSummary]
    let statusCounts: [HARStatusBucket]
    let slowestPhase: HARPhaseAverage?

    var isEmpty: Bool { requestCount == 0 }
}

/// The "Traffic Insights" idea from Rockxy, applied to a HAR someone already
/// exported: what was slow, what failed, where the bytes went and which phase
/// dominates. Pure analysis — no networking.
enum HARTrafficAnalyzer {
    static func insights(for traffic: HARTraffic, slowestLimit: Int = 8) -> HARInsights {
        let entries = traffic.entries
        let durations = entries.map(\.duration).sorted()
        let failures = entries.filter(\.isFailure)
        let cached = entries.filter(\.isFromCache)

        var hostTotals: [String: (requests: Int, failures: Int, bytes: Int, total: Double, slowest: Double)] = [:]
        for entry in entries {
            var totals = hostTotals[entry.host] ?? (0, 0, 0, 0, 0)
            totals.requests += 1
            if entry.isFailure { totals.failures += 1 }
            totals.bytes += entry.sizeBytes
            totals.total += entry.duration
            totals.slowest = max(totals.slowest, entry.duration)
            hostTotals[entry.host] = totals
        }
        let hosts =
            hostTotals
            .map { host, totals in
                HARHostSummary(
                    host: host, requests: totals.requests, failures: totals.failures,
                    bytes: totals.bytes,
                    averageMilliseconds: totals.requests > 0 ? totals.total / Double(totals.requests) : 0,
                    slowestMilliseconds: totals.slowest
                )
            }
            .sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.requests > rhs.requests
            }

        var statusCounts: [Int: Int] = [:]
        for entry in entries { statusCounts[entry.response.status, default: 0] += 1 }

        var phaseTotals: [String: (total: Double, count: Int)] = [:]
        for entry in entries {
            for phase in entry.timings.phases {
                var totals = phaseTotals[phase.name] ?? (0, 0)
                totals.total += phase.milliseconds
                totals.count += 1
                phaseTotals[phase.name] = totals
            }
        }
        let slowestPhase =
            phaseTotals
            .map { name, totals in
                HARPhaseAverage(
                    name: name,
                    milliseconds: totals.count > 0 ? totals.total / Double(totals.count) : 0)
            }
            .max { $0.milliseconds < $1.milliseconds }

        return HARInsights(
            requestCount: entries.count,
            failureCount: failures.count,
            redirectCount: entries.filter(\.isRedirect).count,
            cachedCount: cached.count,
            transferBytes: entries.reduce(0) { $0 + $1.sizeBytes },
            contentBytes: entries.reduce(0) { $0 + $1.response.content.size },
            averageMilliseconds: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
            p95Milliseconds: percentile(durations, fraction: 0.95),
            slowestMilliseconds: durations.last ?? 0,
            slowest: entries.sorted { $0.duration > $1.duration }.prefix(slowestLimit).map { $0 },
            hosts: hosts,
            statusCounts: statusCounts.map { HARStatusBucket(code: $0.key, count: $0.value) }
                .sorted { $0.code < $1.code },
            slowestPhase: slowestPhase
        )
    }

    /// Nearest-rank percentile over an ascending array.
    static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[max(0, min(sorted.count - 1, rank))]
    }

    static func markdownReport(for traffic: HARTraffic, redacted: Bool = true) -> String {
        let insights = insights(for: traffic)
        var lines: [String] = []
        lines.append("# HTTP traffic report")
        lines.append("")
        let source = traffic.creator.map { " recorded by \($0)" } ?? ""
        lines.append("\(insights.requestCount) requests\(source).")
        if let started = traffic.startedAt {
            lines.append("Started \(started.formatted(date: .abbreviated, time: .standard)).")
        }
        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append("| Metric | Value |")
        lines.append("| --- | --- |")
        lines.append("| Requests | \(insights.requestCount) |")
        lines.append("| Failures (4xx/5xx/blocked) | \(insights.failureCount) |")
        lines.append("| Redirects | \(insights.redirectCount) |")
        lines.append("| Served from cache | \(insights.cachedCount) |")
        lines.append("| Transferred | \(bytes(insights.transferBytes)) |")
        lines.append("| Content size | \(bytes(insights.contentBytes)) |")
        lines.append("| Average time | \(HAREntry.milliseconds(insights.averageMilliseconds)) |")
        lines.append("| p95 time | \(HAREntry.milliseconds(insights.p95Milliseconds)) |")
        if let phase = insights.slowestPhase {
            lines.append("| Slowest phase (avg) | \(phase.name) · \(HAREntry.milliseconds(phase.milliseconds)) |")
        }
        lines.append("")

        if !insights.slowest.isEmpty {
            lines.append("## Slowest requests")
            lines.append("")
            lines.append("| Time | Status | Method | URL | Size |")
            lines.append("| --- | --- | --- | --- | --- |")
            for entry in insights.slowest {
                lines.append(
                    "| \(entry.durationLabel) | \(entry.statusLabel) | \(entry.request.method) | "
                        + "\(urlCell(for: entry, redacted: redacted)) | \(bytes(entry.sizeBytes)) |")
            }
            lines.append("")
        }

        let failures = traffic.entries.filter(\.isFailure).sorted { $0.duration > $1.duration }
        if !failures.isEmpty {
            lines.append("## Failures")
            lines.append("")
            lines.append("| Status | Method | URL | Time |")
            lines.append("| --- | --- | --- | --- |")
            for entry in failures.prefix(20) {
                lines.append(
                    "| \(entry.statusLabel) | \(entry.request.method) | "
                        + "\(urlCell(for: entry, redacted: redacted)) | \(entry.durationLabel) |")
            }
            lines.append("")
        }

        lines.append("## Hosts")
        lines.append("")
        lines.append("| Host | Requests | Failures | Transferred | Average |")
        lines.append("| --- | --- | --- | --- | --- |")
        for host in insights.hosts.prefix(15) {
            lines.append(
                "| \(host.host) | \(host.requests) | \(host.failures) | \(bytes(host.bytes)) | "
                    + "\(HAREntry.milliseconds(host.averageMilliseconds)) |")
        }
        lines.append("")

        if !insights.statusCounts.isEmpty {
            let statuses = insights.statusCounts.map { "\($0.code) ×\($0.count)" }.joined(separator: ", ")
            lines.append("Status codes: \(statuses)")
            lines.append("")
        }
        if redacted {
            lines.append(
                "_Authorization, cookie and credential-looking query values were redacted. The loaded capture is unchanged._"
            )
        }
        return lines.joined(separator: "\n")
    }

    private static func urlCell(for entry: HAREntry, redacted: Bool) -> String {
        let target = entry.host + entry.path
        let value = redacted ? HARRedaction.url(target) : target
        return value.replacingOccurrences(of: "|", with: "\\|")
    }

    static func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
