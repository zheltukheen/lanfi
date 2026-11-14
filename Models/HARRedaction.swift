import Foundation

/// One practical idea borrowed from Rockxy's privacy work: a captured session
/// is full of credentials, so anything LanFi writes out or copies can be
/// redacted while the loaded capture stays untouched.
enum HARRedaction {
    static let placeholder = "‹redacted›"

    private static let sensitiveHeaders: Set<String> = [
        "authorization", "proxy-authorization", "cookie", "set-cookie", "www-authenticate",
        "x-api-key", "x-auth-token", "x-csrf-token", "x-xsrf-token", "x-session-token",
        "x-amz-security-token", "x-goog-api-key", "api-key", "apikey",
    ]

    private static let sensitiveParameters: Set<String> = [
        "token", "access_token", "id_token", "refresh_token", "authtoken", "auth",
        "api_key", "apikey", "key", "secret", "client_secret", "password", "passwd",
        "pwd", "session", "sessionid", "session_id", "cookie", "sig", "signature",
        "code", "state", "nonce",
    ]

    static func isSensitiveHeader(_ name: String) -> Bool {
        sensitiveHeaders.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func isSensitiveParameter(_ name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        if sensitiveParameters.contains(normalized) { return true }
        return normalized.hasSuffix("_token") || normalized.hasSuffix("_secret")
            || normalized.hasSuffix("_key")
    }

    static func headers(_ headers: [HARHeader]) -> [HARHeader] {
        headers.map { header in
            guard isSensitiveHeader(header.name) else { return header }
            // Keep the scheme so "Bearer" vs "Basic" remains readable.
            if let scheme = header.value.split(separator: " ").first, header.value.contains(" ") {
                return HARHeader(name: header.name, value: "\(scheme) \(placeholder)")
            }
            return HARHeader(name: header.name, value: placeholder)
        }
    }

    static func query(_ items: [HARQueryItem]) -> [HARQueryItem] {
        items.map { item in
            guard isSensitiveParameter(item.name) else { return item }
            return HARQueryItem(name: item.name, value: placeholder)
        }
    }

    /// Redacts the values of credential-looking query parameters in a URL.
    /// Works on the raw (already percent-encoded) string so the rest of the
    /// URL keeps its exact encoding.
    static func url(_ value: String) -> String {
        guard let questionMark = value.firstIndex(of: "?") else { return value }
        let base = String(value[..<questionMark])
        let queryStart = value.index(after: questionMark)
        let fragmentStart = value[queryStart...].firstIndex(of: "#") ?? value.endIndex
        let queryText = String(value[queryStart..<fragmentStart])
        let fragment = String(value[fragmentStart...])
        guard !queryText.isEmpty else { return value }
        let redacted =
            queryText
            .split(separator: "&", omittingEmptySubsequences: false)
            .map { pair -> String in
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let name = parts.first else { return String(pair) }
                let decodedName =
                    String(name).removingPercentEncoding ?? String(name)
                guard isSensitiveParameter(decodedName) else { return String(pair) }
                return "\(name)=\(placeholder)"
            }
            .joined(separator: "&")
        return base + "?" + redacted + fragment
    }

    static func body(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        // A JSON body may carry a password or token field; redact it without
        // pretending to rewrite arbitrary payloads.
        guard var object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else {
            return text
        }
        object = redactJSON(object)
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return text }
        return String(decoding: data, as: UTF8.self)
    }

    private static func redactJSON(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues { child in redactJSON(child) }.reduce(into: [String: Any]()) {
                result, pair in
                result[pair.key] = isSensitiveParameter(pair.key) ? placeholder : pair.value
            }
        }
        if let array = value as? [Any] {
            return array.map { redactJSON($0) }
        }
        return value
    }
}
