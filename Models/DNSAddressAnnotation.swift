import Foundation

/// Country and network for one resolved address. Kept apart from the DNS
/// answer so a failed annotation never hides the record itself.
struct DNSAddressAnnotation: Equatable, Sendable, Identifiable {
    let address: String
    let country: String
    let countryCode: String
    let asn: Int?
    let organization: String

    var id: String { address }

    init(address: String, country: String, countryCode: String, asn: Int?, organization: String) {
        self.address = address
        self.country = country
        self.countryCode = countryCode
        self.asn = asn
        self.organization = organization
    }

    init(report: GeoIPReport) {
        self.init(
            address: report.ip, country: report.country, countryCode: report.countryCode,
            asn: report.asn, organization: report.organization.isEmpty ? report.isp : report.organization)
    }

    /// "🇺🇸 US · AS15169 · Google LLC", dropping the parts that are missing.
    var summary: String {
        var parts: [String] = []
        let flag = Self.flag(for: countryCode)
        let country = countryCode.isEmpty ? self.country : countryCode
        let place = [flag, country].filter { !$0.isEmpty }.joined(separator: " ")
        if !place.isEmpty { parts.append(place) }
        if let asn { parts.append("AS\(asn)") }
        if !organization.isEmpty { parts.append(organization) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    static func flag(for code: String) -> String {
        let upper = code.uppercased()
        guard upper.count == 2 else { return "" }
        let scalars = upper.unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value)
        }
        guard scalars.count == 2 else { return "" }
        return String(String.UnicodeScalarView(scalars))
    }
}
