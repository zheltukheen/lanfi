import Foundation

/// A host and optional port parsed from a free-form tool field.
///
/// Lives in the core module because every probe screen, the MCP tools and the
/// route monitor parse the same field; the app target only re-uses it.
public struct ToolTarget: Equatable, Sendable {
    public let host: String
    public let port: UInt16?

    public init(host: String, port: UInt16?) {
        self.host = host
        self.port = port
    }

    public var display: String {
        let renderedHost = host.contains(":") ? "[\(host)]" : host
        guard let port else { return renderedHost }
        return "\(renderedHost):\(port)"
    }

    /// Accepts `host`, `host:port`, `scheme://host[:port][/path]` and
    /// `[ipv6]:port`. Returns nil for empty or obviously malformed input.
    public static func parse(_ raw: String, defaultPort: UInt16? = nil) -> ToolTarget? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }

        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            let host = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            guard !host.isEmpty else { return nil }
            if rest.isEmpty { return ToolTarget(host: host, port: defaultPort) }
            guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()), port > 0 else {
                return nil
            }
            return ToolTarget(host: host, port: port)
        }

        let colonCount = value.reduce(into: 0) { count, character in
            if character == ":" { count += 1 }
        }
        if colonCount == 1, let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            let portText = String(value[value.index(after: colon)...])
            guard !host.isEmpty, let port = UInt16(portText), port > 0 else { return nil }
            return ToolTarget(host: host, port: port)
        }
        if colonCount > 1 {
            return ToolTarget(host: value, port: defaultPort)
        }
        return ToolTarget(host: value, port: defaultPort)
    }
}
