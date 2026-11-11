import Foundation

enum WhoisParser {
    static func parse(_ data: Data, query: String) throws -> WhoisReport {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { throw WhoisError.invalidResponse }

        let objectClass = object["objectClassName"] as? String ?? "domain"
        let name =
            (object["ldhName"] as? String)
            ?? (object["name"] as? String)
            ?? (object["handle"] as? String)
            ?? query
        let statuses = object["status"] as? [String] ?? []
        let events = (object["events"] as? [[String: Any]] ?? []).compactMap {
            event -> WhoisEvent? in
            guard let action = event["eventAction"] as? String else { return nil }
            return WhoisEvent(action: action, date: parseDate(event["eventDate"] as? String))
        }
        let nameservers = (object["nameservers"] as? [[String: Any]] ?? []).compactMap {
            ($0["ldhName"] as? String)?.lowercased()
        }
        let registrar = findRegistrar(in: object["entities"] as? [[String: Any]] ?? [])

        return WhoisReport(
            query: query,
            objectType: objectClass,
            name: name,
            handle: object["handle"] as? String,
            registrar: registrar,
            statuses: statuses,
            events: events,
            nameservers: nameservers
        )
    }

    private static func findRegistrar(in entities: [[String: Any]]) -> String? {
        for entity in entities {
            let roles = entity["roles"] as? [String] ?? []
            if roles.contains("registrar"), let name = vcardName(entity) {
                return name
            }
        }
        for entity in entities {
            if let nested = entity["entities"] as? [[String: Any]],
                let name = findRegistrar(in: nested)
            {
                return name
            }
        }
        return nil
    }

    private static func vcardName(_ entity: [String: Any]) -> String? {
        guard let vcard = entity["vcardArray"] as? [Any],
            vcard.count > 1,
            let properties = vcard[1] as? [[Any]]
        else { return nil }
        for property in properties where property.count >= 4 {
            guard property[0] as? String == "fn" else { continue }
            return property[3] as? String
        }
        return nil
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct WhoisClient {
    func lookup(_ query: String) async throws -> WhoisReport {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            throw WhoisError.invalidTarget
        }
        let isIP = IPv4Address(trimmed) != nil
        let path = isIP ? "ip" : "domain"
        guard
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://rdap.org/\(path)/\(encoded)")
        else { throw WhoisError.invalidTarget }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw WhoisError.httpStatus(http.statusCode)
        }
        return try WhoisParser.parse(data, query: trimmed)
    }
}
