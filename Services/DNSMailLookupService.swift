import Foundation

struct DNSMailLookupService: Sendable {
    static let commonDKIMSelectors = [
        "default", "google", "selector1", "selector2", "mail", "dkim",
    ]

    func lookup(domain: String, resolver: DNSResolver) async -> DNSMailReport {
        async let mx = values(host: domain, type: .mx, resolver: resolver)
        async let txt = values(host: domain, type: .txt, resolver: resolver)
        async let dmarc = values(host: "_dmarc.\(domain)", type: .txt, resolver: resolver)

        var dkim: [String: [String]] = [:]
        await withTaskGroup(of: (String, [String]).self) { group in
            for selector in Self.commonDKIMSelectors {
                group.addTask {
                    let records = await values(
                        host: "\(selector)._domainkey.\(domain)", type: .txt,
                        resolver: resolver)
                    return (selector, records)
                }
            }
            for await (selector, records) in group where !records.isEmpty {
                dkim[selector] = records
            }
        }

        return DNSMailAnalyzer.analyze(
            domain: domain,
            mx: await mx,
            txt: await txt,
            dmarc: await dmarc,
            dkim: dkim
        )
    }

    private func values(host: String, type: DNSRecordType, resolver: DNSResolver) async -> [String] {
        guard
            let result = try? await UDPDNSClient().lookup(
                host: host, type: type, resolver: resolver, timeout: 5)
        else { return [] }
        return result.records.map(\.value)
    }
}
