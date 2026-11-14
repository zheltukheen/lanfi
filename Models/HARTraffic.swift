import Foundation

/// One HTTP header as recorded in a HAR file.
struct HARHeader: Equatable, Hashable {
    let name: String
    let value: String
}

/// A query parameter or cookie pair.
struct HARQueryItem: Equatable, Hashable {
    let name: String
    let value: String
}

struct HARPostData: Equatable {
    let mimeType: String
    let text: String?
    let params: [HARQueryItem]

    var byteCount: Int { text?.utf8.count ?? 0 }
}

struct HARRequest: Equatable {
    let method: String
    let url: String
    let httpVersion: String
    let headers: [HARHeader]
    let query: [HARQueryItem]
    let cookies: [HARQueryItem]
    let postData: HARPostData?
}

struct HARContent: Equatable {
    /// Uncompressed size reported by the browser.
    let size: Int
    let compression: Int?
    let mimeType: String
    let text: String?
    let encoding: String?
}

struct HARResponse: Equatable {
    let status: Int
    let statusText: String
    let httpVersion: String
    let headers: [HARHeader]
    let content: HARContent
    let redirectURL: String?
    /// Bytes actually transferred, when the browser measured them.
    let transferSize: Int

    var mimeType: String { content.mimeType }
}

/// HAR records a phase duration of -1 when the phase did not happen.
struct HARTimings: Equatable {
    let blocked: Double?
    let dns: Double?
    let connect: Double?
    let send: Double?
    let wait: Double?
    let receive: Double?
    let ssl: Double?

    static let empty = HARTimings(
        blocked: nil, dns: nil, connect: nil, send: nil, wait: nil, receive: nil, ssl: nil)

    var phases: [(name: String, milliseconds: Double)] {
        [
            ("Blocked", blocked), ("DNS", dns), ("Connect", connect), ("TLS", ssl),
            ("Send", send), ("Wait", wait), ("Receive", receive),
        ].compactMap { name, value in value.map { (name, $0) } }
    }

    var total: Double { phases.reduce(0) { $0 + $1.milliseconds } }
}

struct HAREntry: Identifiable, Equatable {
    let id: String
    let started: Date?
    /// Entry time in milliseconds as recorded (or the sum of the phases).
    let duration: Double
    let serverIP: String?
    let connection: String?
    let request: HARRequest
    let response: HARResponse
    let timings: HARTimings
    let isFromCache: Bool

    private var components: URLComponents? { URLComponents(string: request.url) }

    var host: String { components?.host ?? request.url }

    var path: String {
        guard let components else { return request.url }
        var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery, !query.isEmpty { path += "?" + query }
        return path
    }

    var scheme: String { components?.scheme ?? "" }

    var isSecure: Bool { scheme.lowercased() == "https" }

    /// Status 0 means the request never completed (blocked, cancelled, TLS error).
    var isFailure: Bool { response.status == 0 || response.status >= 400 }

    var isRedirect: Bool { (300..<400).contains(response.status) }

    var statusLabel: String { response.status == 0 ? String(localized: "Failed") : "\(response.status)" }

    var sizeBytes: Int { max(0, response.transferSize) }

    var durationLabel: String { Self.milliseconds(duration) }

    var startedLabel: String {
        guard let started else { return "—" }
        return started.formatted(date: .omitted, time: .standard)
    }

    static func milliseconds(_ value: Double) -> String {
        if value < 1 { return String(format: "%.1f ms", value) }
        if value < 1000 { return String(format: "%.0f ms", value) }
        return String(format: "%.2f s", value / 1000)
    }
}

struct HARTraffic: Equatable {
    let version: String?
    let creator: String?
    let entries: [HAREntry]

    var hosts: [String] { Array(Set(entries.map(\.host))).sorted() }

    var startedAt: Date? { entries.compactMap(\.started).min() }
}

enum HARStatusFilter: String, CaseIterable, Identifiable {
    case all
    case success
    case redirect
    case clientError
    case serverError
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return String(localized: "All statuses")
        case .success: return String(localized: "Success (2xx)")
        case .redirect: return String(localized: "Redirect (3xx)")
        case .clientError: return String(localized: "Client error (4xx)")
        case .serverError: return String(localized: "Server error (5xx)")
        case .failed: return String(localized: "Failed / blocked")
        }
    }

    func matches(_ entry: HAREntry) -> Bool {
        switch self {
        case .all: return true
        case .success: return (200..<300).contains(entry.response.status)
        case .redirect: return entry.isRedirect
        case .clientError: return (400..<500).contains(entry.response.status)
        case .serverError: return entry.response.status >= 500
        case .failed: return entry.response.status == 0
        }
    }
}

enum HARError: Equatable, LocalizedError {
    case invalidJSON(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return String(localized: "This file is not valid JSON: \(detail)")
        case .invalidFormat(let detail):
            return detail
        }
    }
}

/// Reads HAR 1.2 archives produced by browser DevTools, Proxyman, Charles,
/// Rockxy and similar tools. LanFi never proxies traffic itself — it analyzes
/// what another tool already recorded.
enum HARParser {
    static func parse(data: Data) throws -> HARTraffic {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HARError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw HARError.invalidFormat(String(localized: "The file is not a HAR object."))
        }
        guard let log = root["log"] as? [String: Any] else {
            throw HARError.invalidFormat(
                String(localized: "No \"log\" object found — this is not a HAR archive."))
        }
        let rawEntries = log["entries"] as? [[String: Any]] ?? []
        let creator = (log["creator"] as? [String: Any])?["name"] as? String
        let version = log["version"] as? String
        let entries = rawEntries.enumerated().compactMap { index, raw in
            parseEntry(raw, index: index)
        }
        return HARTraffic(version: version, creator: creator, entries: entries)
    }

    static func parseEntry(_ raw: [String: Any], index: Int) -> HAREntry? {
        guard let requestObject = raw["request"] as? [String: Any],
            let url = requestObject["url"] as? String,
            !url.isEmpty
        else { return nil }
        let responseObject = raw["response"] as? [String: Any] ?? [:]
        let timingsObject = raw["timings"] as? [String: Any] ?? [:]

        let request = HARRequest(
            method: (requestObject["method"] as? String) ?? "GET",
            url: url,
            httpVersion: (requestObject["httpVersion"] as? String) ?? "",
            headers: headers(requestObject["headers"]),
            query: pairs(requestObject["queryString"]),
            cookies: pairs(requestObject["cookies"]),
            postData: postData(requestObject["postData"])
        )

        let contentObject = responseObject["content"] as? [String: Any] ?? [:]
        let contentSize = int(contentObject["size"]) ?? 0
        let content = HARContent(
            size: contentSize,
            compression: int(contentObject["compression"]),
            mimeType: (contentObject["mimeType"] as? String) ?? "",
            text: contentObject["text"] as? String,
            encoding: contentObject["_encoding"] as? String ?? contentObject["encoding"] as? String
        )
        // Chrome writes `_transferSize`; the HAR spec uses `bodySize`.
        let transferSize = int(responseObject["_transferSize"]) ?? int(responseObject["bodySize"]) ?? contentSize
        let response = HARResponse(
            status: int(responseObject["status"]) ?? 0,
            statusText: (responseObject["statusText"] as? String) ?? "",
            httpVersion: (responseObject["httpVersion"] as? String) ?? "",
            headers: headers(responseObject["headers"]),
            content: content,
            redirectURL: responseObject["redirectURL"] as? String,
            transferSize: transferSize < 0 ? contentSize : transferSize
        )

        let timings = HARTimings(
            blocked: duration(timingsObject["blocked"]),
            dns: duration(timingsObject["dns"]),
            connect: duration(timingsObject["connect"]),
            send: duration(timingsObject["send"]),
            wait: duration(timingsObject["wait"]),
            receive: duration(timingsObject["receive"]),
            ssl: duration(timingsObject["ssl"])
        )
        let cacheObject = raw["cache"] as? [String: Any]
        let isFromCache =
            (cacheObject?["beforeRequest"] as? [String: Any]) != nil
            || (cacheObject?["afterRequest"] as? [String: Any]) != nil

        return HAREntry(
            id: "\(index)-\(url)",
            started: date(raw["startedDateTime"]),
            duration: duration(raw["time"]) ?? timings.total,
            serverIP: raw["serverIPAddress"] as? String,
            connection: raw["connection"] as? String,
            request: request,
            response: response,
            timings: timings,
            isFromCache: isFromCache
        )
    }

    // MARK: - Field readers

    private static func headers(_ value: Any?) -> [HARHeader] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return HARHeader(name: name, value: (item["value"] as? String) ?? "")
        }
    }

    private static func pairs(_ value: Any?) -> [HARQueryItem] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return HARQueryItem(name: name, value: (item["value"] as? String) ?? "")
        }
    }

    private static func postData(_ value: Any?) -> HARPostData? {
        guard let object = value as? [String: Any] else { return nil }
        return HARPostData(
            mimeType: (object["mimeType"] as? String) ?? "",
            text: object["text"] as? String,
            params: (object["params"] as? [[String: Any]] ?? []).compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                return HARQueryItem(name: name, value: (item["value"] as? String) ?? "")
            }
        )
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    /// HAR uses -1 for "this phase did not happen".
    private static func duration(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            let milliseconds = number.doubleValue
            return milliseconds < 0 ? nil : milliseconds
        }
        if let text = value as? String, let milliseconds = Double(text), milliseconds >= 0 {
            return milliseconds
        }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
