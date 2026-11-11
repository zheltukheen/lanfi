import Foundation
import Network

enum GeoIPParser {
    static func parse(_ data: Data, query: String) throws -> GeoIPReport {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw GeoIPError.invalidResponse }
        guard object["success"] as? Bool == true else {
            throw GeoIPError.lookupFailed(
                object["message"] as? String ?? "Address not found.")
        }
        guard let ip = object["ip"] as? String,
            let latitude = object["latitude"] as? Double,
            let longitude = object["longitude"] as? Double
        else { throw GeoIPError.invalidResponse }

        let connection = object["connection"] as? [String: Any] ?? [:]
        let timezone = object["timezone"] as? [String: Any] ?? [:]
        return GeoIPReport(
            query: query,
            ip: ip,
            type: object["type"] as? String ?? "IP",
            continent: object["continent"] as? String ?? "",
            country: object["country"] as? String ?? "",
            countryCode: object["country_code"] as? String ?? "",
            flag: object["flag"] as? String ?? "",
            region: object["region"] as? String ?? "",
            city: object["city"] as? String ?? "",
            latitude: latitude,
            longitude: longitude,
            asn: connection["asn"] as? Int,
            organization: connection["org"] as? String ?? "",
            isp: connection["isp"] as? String ?? "",
            timezone: timezone["id"] as? String ?? "",
            utcOffset: timezone["utc"] as? String ?? ""
        )
    }
}

struct GeoIPClient {
    func lookup(_ query: String?) async throws -> GeoIPReport {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let address: String
        if trimmed.isEmpty {
            address = ""
        } else if IPv4Address(trimmed) != nil || IPv6Address(trimmed) != nil {
            address = trimmed
        } else {
            address = try await resolve(trimmed)
        }

        let urlString =
            address.isEmpty
            ? "https://ipwho.is/"
            : "https://ipwho.is/\(address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? address)"
        guard let url = URL(string: urlString) else { throw GeoIPError.invalidTarget }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw GeoIPError.httpStatus(http.statusCode)
        }
        return try GeoIPParser.parse(data, query: trimmed.isEmpty ? "My IP" : trimmed)
    }

    private func resolve(_ host: String) async throws -> String {
        for type in [DNSRecordType.a, .aaaa] {
            if let lookup = try? await UDPDNSClient().lookup(
                host: host, type: type, resolver: .cloudflare, timeout: 4),
                let record = lookup.records.first
            {
                return record.value
            }
        }
        throw GeoIPError.invalidTarget
    }
}
