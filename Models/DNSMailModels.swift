import Foundation

enum DNSLookupTab: String, CaseIterable, Identifiable, Sendable {
    case records, mail, reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .records: return String(localized: "Records")
        case .mail: return String(localized: "Mail")
        case .reports: return String(localized: "Reports")
        }
    }
}

struct DMARCPolicy: Equatable, Sendable {
    let raw: String
    let policy: String
    let rua: String?
    let ruf: String?
}

struct DKIMRecord: Identifiable, Equatable, Sendable {
    let selector: String
    let value: String

    var id: String { selector }
}

struct DNSMailReport: Equatable, Sendable {
    let domain: String
    let mx: [String]
    let spf: String?
    let dmarc: DMARCPolicy?
    let dkim: [DKIMRecord]
    let issues: [String]

    var hasMX: Bool { !mx.isEmpty }
    var hasSPF: Bool { spf != nil }
    var hasDMARC: Bool { dmarc != nil }
    var hasDKIM: Bool { !dkim.isEmpty }

    var passedChecks: Int {
        [hasMX, hasSPF, hasDMARC, hasDKIM].filter { $0 }.count
    }
}

enum DNSMailAnalyzer {
    static func analyze(
        domain: String,
        mx: [String],
        txt: [String],
        dmarc: [String],
        dkim: [String: [String]]
    ) -> DNSMailReport {
        let spfValues = txt.filter {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("v=spf1")
        }
        let dmarcValue = dmarc.first {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("v=dmarc1")
        }
        let policy = dmarcValue.map(parseDMARC)
        let dkimRecords = dkim.keys.sorted().compactMap { selector -> DKIMRecord? in
            guard
                let value = dkim[selector]?.first(where: {
                    $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("v=dkim1")
                })
            else { return nil }
            return DKIMRecord(selector: selector, value: value)
        }

        var issues: [String] = []
        if mx.isEmpty {
            issues.append(String(localized: "No MX records: this domain cannot receive mail."))
        }
        if spfValues.isEmpty {
            issues.append(String(localized: "No SPF record: receivers cannot tell which servers may send mail."))
        }
        if dmarcValue == nil {
            issues.append(String(localized: "No DMARC record: receivers have no policy for failing mail."))
        } else if policy?.policy == "none" {
            issues.append(String(localized: "DMARC is p=none: reports only, failing mail is not blocked."))
        }
        if dkimRecords.isEmpty {
            issues.append(String(localized: "No DKIM key found at the common selectors."))
        }

        return DNSMailReport(
            domain: domain,
            mx: mx,
            spf: spfValues.first,
            dmarc: policy,
            dkim: dkimRecords,
            issues: issues
        )
    }

    private static func parseDMARC(_ value: String) -> DMARCPolicy {
        var tags: [String: String] = [:]
        for part in value.split(separator: ";") {
            let pieces = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pieces.count == 2 else { continue }
            tags[pieces[0].lowercased()] = pieces[1]
        }
        return DMARCPolicy(
            raw: value,
            policy: tags["p"]?.lowercased() ?? "none",
            rua: tags["rua"],
            ruf: tags["ruf"]
        )
    }
}
