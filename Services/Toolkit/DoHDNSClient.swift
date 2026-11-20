import Foundation

/// A DNS-over-HTTPS endpoint. DoH is compared against the plain UDP answers
/// because a network that rewrites port 53 is invisible to both otherwise.
struct DoHResolver: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let endpoint: URL

    static let cloudflare = DoHResolver(
        id: "doh-cloudflare", name: "Cloudflare DoH",
        endpoint: URL(string: "https://cloudflare-dns.com/dns-query")!)
    static let google = DoHResolver(
        id: "doh-google", name: "Google DoH",
        endpoint: URL(string: "https://dns.google/dns-query")!)

    static let builtIn: [DoHResolver] = [.cloudflare, .google]

    static func custom(_ text: String) -> DoHResolver? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host != nil else {
            return nil
        }
        return DoHResolver(id: "doh:\(trimmed)", name: url.host ?? trimmed, endpoint: url)
    }
}

/// Resolves through a DoH JSON endpoint. The JSON API is used rather than the
/// wire format because it reports the same records the UDP path parses, so the
/// comparison compares answers instead of encodings.
struct DoHDNSClient: Sendable {
    var session: URLSession = .shared

    func lookup(
        host: String,
        type: DNSRecordType,
        resolver: DoHResolver,
        timeout: TimeInterval = 6
    ) async throws -> DNSLookupResult {
        guard var components = URLComponents(url: resolver.endpoint, resolvingAgainstBaseURL: false)
        else { throw DNSClientError.invalidResolver(resolver.endpoint.absoluteString) }
        components.queryItems = [
            URLQueryItem(name: "name", value: host),
            URLQueryItem(name: "type", value: type.label),
        ]
        guard let url = components.url else {
            throw DNSClientError.invalidResolver(resolver.endpoint.absoluteString)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")

        let started = Date()
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DNSClientError.http(http.statusCode)
        }
        return try Self.parse(
            data, host: host, resolverName: resolver.name,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000))
    }

    /// Parses the `application/dns-json` shape used by Cloudflare and Google.
    static func parse(
        _ data: Data,
        host: String,
        resolverName: String,
        milliseconds: Int
    ) throws -> DNSLookupResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DNSClientError.invalidResponse("The DoH response is not JSON.")
        }
        if let status = root["Status"] as? Int, status != 0 {
            throw DNSClientError.serverStatus(status)
        }
        let answers = root["Answer"] as? [[String: Any]] ?? []
        let records = answers.compactMap { answer -> DNSRecord? in
            guard
                let rawType = answer["type"] as? Int,
                let type = DNSRecordType(rawValue: UInt16(truncatingIfNeeded: rawType)),
                let data = answer["data"] as? String
            else { return nil }
            let ttl = UInt32(clamping: answer["TTL"] as? Int ?? 0)
            let name = (answer["name"] as? String ?? host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            var value = data
            var priority: UInt16?
            if type == .mx, let space = data.firstIndex(of: " ") {
                priority = UInt16(data[data.startIndex..<space])
                value = String(data[data.index(after: space)...])
            }
            return DNSRecord(
                name: name, type: type, ttl: ttl, priority: priority,
                value: value.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
        }
        return DNSLookupResult(
            host: host, resolver: resolverName, records: records, milliseconds: milliseconds)
    }
}
