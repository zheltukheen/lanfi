import Foundation

/// How a resolver was reached in a comparison run.
enum DNSComparisonTransport: String, Sendable {
    case udp
    case doh

    var label: String {
        switch self {
        case .udp: return "UDP"
        case .doh: return "DoH"
        }
    }
}

struct DNSComparisonEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let transport: DNSComparisonTransport
    let records: [DNSRecord]
    let milliseconds: Int
    let failure: String?

    /// The answer as a set of values, so TTLs and record order do not make two
    /// identical answers look different.
    var answerValues: [String] { records.map(\.value).sorted() }
    var answerText: String {
        if let failure { return failure }
        return records.isEmpty ? "No records" : answerValues.joined(separator: ", ")
    }
}

/// One query sent to several resolvers over different transports.
struct DNSComparison: Equatable, Sendable {
    let host: String
    let type: DNSRecordType
    let entries: [DNSComparisonEntry]

    var answeredEntries: [DNSComparisonEntry] {
        entries.filter { $0.failure == nil }
    }

    /// True when two resolvers that both answered returned different values.
    /// A resolver that returned nothing at all still counts: an empty answer
    /// next to a populated one is exactly the hijack/rewrite case.
    var answersDisagree: Bool {
        Set(answeredEntries.map(\.answerValues)).count > 1
    }

    var failedCount: Int { entries.filter { $0.failure != nil }.count }

    /// Plain text for the Copy button and for pasting into a ticket. One row
    /// per resolver, failed resolvers kept and marked, then the verdict.
    var exportText: String {
        var lines = ["LanFi DNS comparison \(host) · \(type.label)", ""]
        for entry in entries {
            if let failure = entry.failure {
                lines.append("\(entry.name)\t\(entry.transport.label)\t! \(failure)")
            } else {
                lines.append(
                    "\(entry.name)\t\(entry.transport.label)\t\(entry.answerText)\t\(entry.milliseconds) ms"
                )
            }
        }
        lines.append("")
        lines.append(summary)
        if failedCount > 0 {
            lines.append("\(failedCount) of \(entries.count) did not answer")
        }
        return lines.joined(separator: "\n")
    }

    var summary: String {
        if entries.isEmpty { return String(localized: "No resolvers were queried.") }
        if answeredEntries.isEmpty { return String(localized: "No resolver answered.") }
        if answersDisagree { return String(localized: "Resolvers disagree on the answer.") }
        return String(localized: "All resolvers agree.")
    }
}
