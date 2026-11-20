import Foundation

/// One line under the answers explaining *why* they look the way they do.
struct DNSAnswerNote: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case info
        case warning
    }

    let id: String
    let kind: Kind
    let text: String
}

/// Reads the shape of a DNS answer. Pure, so every rule can be tested with
/// recorded answers instead of the network.
///
/// The rules only use what LanFi can actually see: the records themselves, the
/// same question asked of the system resolver, and the networks the addresses
/// belong to when the GeoIP annotation arrived. Nothing is inferred about
/// proxies LanFi cannot inspect.
enum DNSAnswerExplanation {
    static func notes(
        records: [DNSRecord], systemRecords: [DNSRecord]?, organizations: [String] = []
    ) -> [DNSAnswerNote] {
        var notes: [DNSAnswerNote] = []
        let addresses = addressValues(records)

        let fakeIP = addresses.filter(isFakeIP)
        if !fakeIP.isEmpty {
            notes.append(
                DNSAnswerNote(
                    id: "fake-ip", kind: .warning,
                    text: String(
                        format: String(
                            localized:
                                "%@ is in 198.18.0.0/15, the range proxy tools use for fake IPs, so a transparent proxy is answering this name."
                        ), fakeIP.joined(separator: ", "))))
        }

        if !addresses.isEmpty, addresses.allSatisfy(isPrivate) {
            notes.append(
                DNSAnswerNote(
                    id: "private", kind: .warning,
                    text: String(
                        localized: "Every address is private, so a local or split-horizon resolver answers this name."))
            )
        }

        let zeroTTL =
            records.contains { $0.type == .a || $0.type == .aaaa }
            && records.filter {
                $0.type == .a || $0.type == .aaaa
            }.allSatisfy { $0.ttl == 0 }
        if zeroTTL {
            notes.append(
                DNSAnswerNote(
                    id: "ttl-zero", kind: .info,
                    text: String(localized: "The TTL is 0, so nothing downstream may cache this answer.")))
        }

        if let systemRecords {
            let systemValues = Set(addressValues(systemRecords))
            let values = Set(addresses)
            if !values.isEmpty, !systemValues.isEmpty, systemValues != values {
                notes.append(
                    DNSAnswerNote(
                        id: "system-differs", kind: .warning,
                        text: String(
                            format: String(
                                localized:
                                    "The system resolver answers differently: %@."),
                            systemValues.sorted().joined(separator: ", "))))
            } else if !values.isEmpty, systemValues == values {
                notes.append(
                    DNSAnswerNote(
                        id: "system-agrees", kind: .info,
                        text: String(localized: "The system resolver returns the same addresses.")))
            }
        }

        let networks = Set(organizations.filter { !$0.isEmpty })
        if networks.count >= 2 {
            notes.append(
                DNSAnswerNote(
                    id: "cdn", kind: .info,
                    text: String(
                        format: String(
                            localized:
                                "The addresses belong to %lld different networks, which is normal for a content network."
                        ),
                        networks.count)))
        }
        return notes
    }

    static func addressValues(_ records: [DNSRecord]) -> [String] {
        records.filter { $0.type == .a || $0.type == .aaaa }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 198.18.0.0/15 — the benchmarking range proxies borrow for fake IPs.
    static func isFakeIP(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 198 else { return false }
        return parts[1] == 18 || parts[1] == 19
    }

    static func isPrivate(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            // IPv6: loopback and unique-local ranges only.
            let lower = value.lowercased()
            if lower == "::1" { return true }
            if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return true }
            if lower.hasPrefix("fe80") { return true }
            return false
        }
        let first = parts[0]
        let second = parts[1]
        if first == 10 { return true }
        if first == 127 { return true }
        if first == 172, (16...31).contains(second) { return true }
        if first == 192, second == 168 { return true }
        if first == 169, second == 254 { return true }
        if first == 100, (64...127).contains(second) { return true }  // CGNAT
        return false
    }
}
