import Foundation

/// Parses the stdout of `/usr/sbin/traceroute -n -m 30 -w 2 -q 1 <host>`.
enum TracerouteParser {

    static func parse(_ output: String, host: String) -> TracerouteReport {
        var hops: [TracerouteHop] = []
        var seenTTLs = Set<Int>()

        for line in output.split(whereSeparator: \.isNewline) {
            guard let hop = parseHop(String(line)), seenTTLs.insert(hop.ttl).inserted else { continue }
            hops.append(hop)
        }

        return TracerouteReport(host: host, hops: hops, startedAt: Date())
    }

    // MARK: - Lines

    private static func parseHop(_ line: String) -> TracerouteHop? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = tokens.first, let ttl = Int(first), (1...255).contains(ttl) else { return nil }

        let body = Array(tokens.dropFirst())
        let address = address(in: body)
        return TracerouteHop(
            ttl: ttl,
            address: address,
            hostname: hostname(in: body),
            milliseconds: milliseconds(in: body),
            timedOut: address == nil
        )
    }

    // MARK: - Fields

    private static func address(in tokens: [String]) -> String? {
        for token in tokens {
            let value = unwrapped(token)
            if isIPAddressLiteral(value) { return value }
        }
        return nil
    }

    private static func hostname(in tokens: [String]) -> String? {
        var candidates: [String] = []
        for token in tokens {
            if token == "*" || token.hasPrefix("!") { continue }
            if isTimeToken(token) { break }
            candidates.append(unwrapped(token))
            if candidates.count == 2 { break }
        }

        guard let first = candidates.first, !first.isEmpty else { return nil }
        if candidates.count > 1, isIPAddressLiteral(candidates[1]) { return first }
        return isIPAddressLiteral(first) ? nil : first
    }

    private static func milliseconds(in tokens: [String]) -> [Double] {
        var values: [Double] = []
        for (index, token) in tokens.enumerated() where token == "ms" {
            guard index > 0, let value = Double(tokens[index - 1]) else { continue }
            values.append(value)
        }
        return values
    }

    // MARK: - Tokens

    private static func isTimeToken(_ token: String) -> Bool {
        token == "ms" || Double(token) != nil
    }

    private static func unwrapped(_ token: String) -> String {
        guard token.hasPrefix("("), token.hasSuffix(")"), token.count > 2 else { return token }
        return String(token.dropFirst().dropLast())
    }

    // MARK: - Address literals

    private static func isIPAddressLiteral(_ text: String) -> Bool {
        isIPv4Literal(text) || isIPv6Literal(text)
    }

    private static func isIPv4Literal(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            (1...3).contains(part.count)
                && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
                && UInt8(part) != nil
        }
    }

    private static func isIPv6Literal(_ text: String) -> Bool {
        guard text.contains(":") else { return false }
        let address = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text
        let halves = address.components(separatedBy: "::")
        guard halves.count <= 2 else { return false }

        var groups: [Substring] = []
        for half in halves where !half.isEmpty {
            groups.append(contentsOf: half.split(separator: ":", omittingEmptySubsequences: false))
        }

        var groupCount = 0
        for (index, group) in groups.enumerated() {
            if index == groups.count - 1, group.contains(".") {
                guard isIPv4Literal(String(group)) else { return false }
                groupCount += 2
            } else {
                guard (1...4).contains(group.count),
                    group.unicodeScalars.allSatisfy({ isHexDigit($0) })
                else { return false }
                groupCount += 1
            }
        }

        return halves.count == 2 ? groupCount < 8 : groupCount == 8
    }

    private static func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
        (48...57).contains(scalar.value)
            || (65...70).contains(scalar.value)
            || (97...102).contains(scalar.value)
    }
}
