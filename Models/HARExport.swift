import Foundation

/// Turns captured HTTP exchanges into the formats a developer actually hands
/// to someone else: a reproducible cURL command, a spreadsheet row or a
/// Markdown report. Everything here is pure and testable.
enum HARExport {
    static func curl(for entry: HAREntry, redacted: Bool = true) -> String {
        let url = redacted ? HARRedaction.url(entry.request.url) : entry.request.url
        var parts = ["curl -X \(entry.request.method)", shellQuote(url, escaped: true)]
        for header in entry.request.headers where !header.name.hasPrefix(":") {
            guard header.name.lowercased() != "content-length" else { continue }
            let value =
                redacted && HARRedaction.isSensitiveHeader(header.name)
                ? redactedHeaderValue(header.value) : header.value
            parts.append("-H")
            parts.append(shellQuote("\(header.name): \(value)", escaped: true))
        }
        if let body = entry.request.postData?.text, !body.isEmpty {
            let text = redacted ? HARRedaction.body(body) : body
            parts.append("--data-raw")
            parts.append(shellQuote(text, escaped: true))
        }
        return parts.joined(separator: " ")
    }

    static func csv(for entries: [HAREntry], redacted: Bool = true) -> String {
        var lines = [
            "started,method,status,host,path,mimeType,transferBytes,contentBytes,timeMs,cached,serverIP"
        ]
        for entry in entries {
            let host = field(entry.host, redacted: false)
            let path = field(entry.path, redacted: redacted)
            lines.append(
                [
                    entry.started.map { iso($0) } ?? "",
                    entry.request.method,
                    entry.response.status == 0 ? "failed" : "\(entry.response.status)",
                    host,
                    path,
                    field(entry.response.mimeType, redacted: false),
                    "\(entry.sizeBytes)",
                    "\(entry.response.content.size)",
                    String(format: "%.1f", entry.duration),
                    entry.isFromCache ? "yes" : "no",
                    entry.serverIP ?? "",
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Rows for the inspector table: started, method, status, duration, size.
    static func summaryLine(for entry: HAREntry) -> String {
        "\(entry.statusLabel) \(entry.request.method) \(entry.host)\(entry.path) · \(entry.durationLabel)"
    }

    private static func redactedHeaderValue(_ value: String) -> String {
        guard let scheme = value.split(separator: " ").first, value.contains(" ") else {
            return HARRedaction.placeholder
        }
        return "\(scheme) \(HARRedaction.placeholder)"
    }

    private static func field(_ value: String, redacted: Bool) -> String {
        let text = redacted ? HARRedaction.url(value) : value
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// POSIX single-quote escaping. `escaped` quotes the value, otherwise the
    /// caller already has a bare token.
    private static func shellQuote(_ value: String, escaped: Bool) -> String {
        guard escaped else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
