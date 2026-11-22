import Foundation
import Network

/// P3.5 — the opt-in half of DNS switching. Everything here is pure so the
/// confirmation sheet and the tests can reason about a change before the app
/// asks for authorization.
struct DNSResolverPlan: Equatable, Identifiable {
    let id = UUID()
    let service: String
    let currentServers: [String]
    let newServers: [String]
    let resolverName: String

    /// An empty list is DHCP: `networksetup` calls that "Empty".
    var isRevertToAutomatic: Bool { newServers.isEmpty }

    var summary: String {
        if isRevertToAutomatic {
            return String(localized: "Restore the DNS servers provided by DHCP.")
        }
        return String(
            format: String(localized: "Use %@ for every DNS query on %@."),
            resolverName, service)
    }
}

enum DNSResolverSwitch {
    /// `networksetup -listallnetworkservices` prefixes disabled services with
    /// `*`; the UI never offers those.
    static func services(from output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("*") && !$0.localizedCaseInsensitiveContains("asterisk") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `networksetup -getdnsservers` prints one address per line, or a single
    /// sentence when DHCP supplies the resolver. Both mean "no manual servers".
    static func servers(from output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.localizedCaseInsensitiveContains("aren't any DNS Servers")
            || trimmed.localizedCaseInsensitiveContains("not set")
        {
            return []
        }
        let addresses = trimmed.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard addresses.allSatisfy(isAddress) else { return [] }
        return addresses
    }

    static func isAddress(_ value: String) -> Bool {
        IPv4Address(value) != nil || IPv6Address(value) != nil
    }

    /// Validation for a manual switch: at least one address, at most three,
    /// every entry an IPv4/IPv6 literal. Hostnames are rejected because
    /// `networksetup` accepts them in ways the rest of the app cannot model.
    static func validate(_ servers: [String]) -> String? {
        guard !servers.isEmpty else { return String(localized: "Choose at least one DNS server.") }
        guard servers.count <= 3 else {
            return String(localized: "Use no more than three DNS servers.")
        }
        guard servers.allSatisfy(isAddress) else {
            return String(localized: "Enter IP addresses, not host names.")
        }
        return nil
    }

    /// The exact command the confirmation sheet describes. Revert uses the
    /// literal `Empty`, which is `networksetup`'s word for DHCP.
    static func setCommand(service: String, servers: [String]) -> String {
        let arguments = servers.isEmpty ? ["Empty"] : servers
        return "networksetup -setdnsservers \(quoted(service)) \(arguments.map(quoted).joined(separator: " "))"
    }

    /// A cache flush alone does not help when mDNSResponder keeps its state;
    /// both commands are part of the switch and of the revert.
    static func flushCommands() -> [String] {
        ["dscacheutil -flushcache", "killall -HUP mDNSResponder"]
    }

    /// The shell script wrapped in one administrator authorization prompt.
    static func authorizedScript(service: String, servers: [String]) -> String {
        ([setCommand(service: service, servers: servers)] + flushCommands())
            .joined(separator: " && ")
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The previous setting, kept so Revert can put back exactly what was there
/// rather than assuming DHCP. Written only after a successful switch.
extension DNSBenchmarkResolver {
    /// The servers a switch would install. The system resolver has none: it is
    /// the state "revert to DHCP" returns to.
    var switchServers: [String] { Self.switchingServers(for: id) }

    var canSwitch: Bool { !switchServers.isEmpty }

    static func switchingServers(for id: String) -> [String] {
        switch id {
        case "cloudflare": return ["1.1.1.1", "1.0.0.1"]
        case "google": return ["8.8.8.8", "8.8.4.4"]
        case "quad9": return ["9.9.9.9", "149.112.112.112"]
        default: return []
        }
    }
}

extension DNSBenchmarkResult {
    var switchServers: [String] { DNSBenchmarkResolver.switchingServers(for: resolverID) }
    var canSwitch: Bool { !switchServers.isEmpty }
}

struct DNSResolverBackup: Codable, Equatable {
    let service: String
    let servers: [String]
    let savedAt: Date

    var isAutomatic: Bool { servers.isEmpty }
}
