import Foundation

/// P3.4 — provider-agnostic VPN detection and leak indicators.
///
/// Nothing here talks to a VPN provider and no credential is ever read: the
/// indicators come from the local route table and `scutil --dns` only. Both are
/// labelled as indicators, not proof.
enum TunnelInterface {
    static let prefixes = ["utun", "ipsec", "ppp", "tun", "tap"]

    static func isTunnel(_ name: String) -> Bool {
        let lower = name.lowercased()
        return prefixes.contains { lower.hasPrefix($0) }
    }
}

struct VPNDetection: Equatable, Sendable {
    let defaultInterface: String?
    let activeTunnels: [String]
    let isFullTunnel: Bool

    static let none = VPNDetection(defaultInterface: nil, activeTunnels: [], isFullTunnel: false)

    /// A tunnel is "in use" when it carries the default route, or at least when
    /// one of its interfaces is up — split tunnels still count.
    var isUp: Bool { isFullTunnel || !activeTunnels.isEmpty }

    var interfaceLabel: String? {
        if isFullTunnel, let defaultInterface { return defaultInterface }
        return activeTunnels.first
    }

    var detail: String {
        guard isUp else { return String(localized: "No VPN tunnel detected.") }
        if isFullTunnel, let defaultInterface {
            return String(localized: "The default route goes through \(defaultInterface).")
        }
        return String(localized: "A tunnel interface is up but it does not carry the default route.")
    }
}

enum VPNDetector {
    static func detect(defaultInterface: String?, activeTunnels: [String]) -> VPNDetection {
        let tunnels = activeTunnels.filter(TunnelInterface.isTunnel)
        let full = defaultInterface.map(TunnelInterface.isTunnel) ?? false
        return VPNDetection(
            defaultInterface: defaultInterface, activeTunnels: tunnels, isFullTunnel: full)
    }
}

// MARK: - DNS

/// One `resolver #n` block from `scutil --dns`.
struct DNSResolverBlock: Equatable, Sendable {
    let index: Int
    let interface: String?
    let nameservers: [String]
    let isDefault: Bool

    var isTunnel: Bool { interface.map(TunnelInterface.isTunnel) ?? false }
}

enum SCUtilDNSOutput {
    static func parse(_ text: String) -> [DNSResolverBlock] {
        var blocks: [DNSResolverBlock] = []
        var index = 0
        var interface: String?
        var servers: [String] = []
        var isDefault = false
        var inBlock = false

        func flush() {
            guard inBlock else { return }
            blocks.append(
                DNSResolverBlock(
                    index: index, interface: interface, nameservers: servers, isDefault: isDefault)
            )
            interface = nil
            servers = []
            isDefault = false
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("resolver #") {
                flush()
                index = Int(line.dropFirst("resolver #".count)) ?? blocks.count + 1
                inBlock = true
                continue
            }
            guard inBlock else { continue }

            if line.hasPrefix("nameserver[") {
                if let colon = line.firstIndex(of: ":") {
                    let value = line[line.index(after: colon)...]
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { servers.append(value) }
                }
            } else if line.hasPrefix("if_index") {
                // `if_index : 21 (utun3)`
                if let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"),
                    open < close
                {
                    interface = String(line[line.index(after: open)..<close])
                }
            } else if line.hasPrefix("flags") {
                isDefault = line.lowercased().contains("default")
            }
        }
        flush()
        return blocks
    }
}

/// Shared by the DNS and IPv6 indicators.
enum LeakStatus: String, Equatable, Sendable {
    case ok
    case leak
    case unknown
}

struct DNSLeakVerdict: Equatable, Sendable {
    let status: LeakStatus
    let usedResolvers: [String]
    let tunnelResolvers: [String]

    static let unknown = DNSLeakVerdict(status: .unknown, usedResolvers: [], tunnelResolvers: [])

    var detail: String {
        switch status {
        case .ok:
            return String(localized: "The resolver in use belongs to the tunnel.")
        case .leak:
            return String(
                localized:
                    "The tunnel pushes \(tunnelResolvers.joined(separator: ", ")) but the system resolver is \(usedResolvers.joined(separator: ", ")). Lookups may leave the tunnel. Indicator only: split DNS does this legitimately."
            )
        case .unknown:
            return String(localized: "Not enough resolver information to judge.")
        }
    }
}

enum VPNDNSIntegrity {
    static func evaluate(vpn: VPNDetection, blocks: [DNSResolverBlock]) -> DNSLeakVerdict {
        let tunnelResolvers = unique(blocks.filter(\.isTunnel).flatMap(\.nameservers))
        let defaultBlock = blocks.first(where: \.isDefault) ?? blocks.first
        let used = unique(defaultBlock?.nameservers ?? [])

        guard vpn.isUp, !tunnelResolvers.isEmpty, !used.isEmpty else {
            return DNSLeakVerdict(status: .unknown, usedResolvers: used, tunnelResolvers: tunnelResolvers)
        }
        let shares = used.contains { tunnelResolvers.contains($0) }
        return DNSLeakVerdict(
            status: shares ? .ok : .leak, usedResolvers: used, tunnelResolvers: tunnelResolvers)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

// MARK: - IPv6

struct IPv6LeakVerdict: Equatable, Sendable {
    let status: LeakStatus
    let defaultInterface: String?

    static let unknown = IPv6LeakVerdict(status: .unknown, defaultInterface: nil)

    var detail: String {
        switch status {
        case .ok:
            return String(localized: "No IPv6 default route escapes the tunnel.")
        case .leak:
            return String(
                localized:
                    "A global IPv6 default route leaves through \(defaultInterface ?? "another interface") while the tunnel is up, so IPv6 traffic may bypass it."
            )
        case .unknown:
            return String(localized: "No tunnel to check IPv6 against.")
        }
    }
}

enum VPNIPv6Integrity {
    static func evaluate(vpn: VPNDetection, ipv6DefaultInterface: String?) -> IPv6LeakVerdict {
        guard vpn.isUp else { return .unknown }
        guard let ipv6DefaultInterface else {
            return IPv6LeakVerdict(status: .ok, defaultInterface: nil)
        }
        let status: LeakStatus = TunnelInterface.isTunnel(ipv6DefaultInterface) ? .ok : .leak
        return IPv6LeakVerdict(status: status, defaultInterface: ipv6DefaultInterface)
    }
}

// MARK: - Route table

enum RouteTableOutput {
    /// Returns the interface of the `default` route, if the table has one.
    static func defaultInterface(_ text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            let fields = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = fields.first, first == "default" else { continue }
            guard let last = fields.last else { continue }
            let name = String(last)
            if name.hasPrefix("en") || name.hasPrefix("utun") || name.hasPrefix("ipsec")
                || name.hasPrefix("ppp") || name.hasPrefix("tun") || name.hasPrefix("tap")
            {
                return name
            }
        }
        return nil
    }
}

// MARK: - Report

struct VPNGuardReport: Equatable, Sendable {
    let vpn: VPNDetection
    let dns: DNSLeakVerdict
    let ipv6: IPv6LeakVerdict
    let checkedAt: Date?

    static let empty = VPNGuardReport(vpn: .none, dns: .unknown, ipv6: .unknown, checkedAt: nil)

    var hasLeak: Bool { dns.status == .leak || ipv6.status == .leak }

    /// Stable signature used to raise one notification per state, not per poll.
    var signature: String {
        "\(vpn.isUp)|\(vpn.interfaceLabel ?? "-")|\(dns.status.rawValue)|\(ipv6.status.rawValue)"
    }
}
