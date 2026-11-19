import Foundation

/// P3.7 — what happened to the default gateway's hardware address.
enum GatewayChange: Equatable, Sendable {
    /// First observation of this gateway on this network.
    case learned(ip: String, mac: String)
    /// The IP stayed the same and the MAC changed: ARP spoofing signature.
    case changed(ip: String, from: String, to: String)
    /// The interface lost its default gateway.
    case cleared(ip: String)

    var isSuspicious: Bool {
        if case .changed = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .learned(let ip, let mac):
            return String(localized: "Gateway \(ip) uses \(mac).")
        case .changed(let ip, let from, let to):
            return String(
                localized:
                    "Gateway \(ip) changed its hardware address from \(from) to \(to) while the IP stayed the same."
            )
        case .cleared(let ip):
            return String(localized: "Gateway \(ip) is no longer the default route.")
        }
    }
}

/// Watches one gateway IP/MAC pair across ARP samples.
///
/// macOS hides the ARP table until Local Network access is granted, so a missing
/// MAC is "unknown", never "changed": an empty table must not fire an alert.
struct GatewayARPWatch: Equatable {
    private(set) var gatewayIP: String?
    private(set) var gatewayMAC: String?
    private(set) var changeCount = 0

    mutating func observe(gateway: String?, entries: [ARPEntry]) -> GatewayChange? {
        guard let gateway, !gateway.isEmpty else {
            guard let previous = gatewayIP else {
                gatewayMAC = nil
                return nil
            }
            gatewayIP = nil
            gatewayMAC = nil
            changeCount = 0
            return .cleared(ip: previous)
        }

        guard gateway == gatewayIP else {
            // A different network: relearn instead of comparing across routers.
            let isFirstObservation = gatewayIP == nil
            gatewayIP = gateway
            gatewayMAC = entries.first { $0.ip == gateway }?.mac
            changeCount = 0
            guard isFirstObservation, let mac = gatewayMAC else { return nil }
            return .learned(ip: gateway, mac: mac)
        }

        guard let mac = entries.first(where: { $0.ip == gateway })?.mac else { return nil }
        guard let previous = gatewayMAC else {
            gatewayMAC = mac
            return .learned(ip: gateway, mac: mac)
        }
        guard previous.caseInsensitiveCompare(mac) != .orderedSame else { return nil }

        gatewayMAC = mac
        changeCount += 1
        return .changed(ip: gateway, from: previous, to: mac)
    }
}

/// P3.7 — compares what the system resolver returned for a canary host with the
/// answer a public resolver gives directly.
///
/// A difference is a *warning*, not proof of an attack: CDNs legitimately return
/// different addresses per resolver and per region. A hijack shows up as a
/// disjoint answer, typically a parking or NXDOMAIN page.
struct ResolverIntegrityCheck: Equatable, Sendable {
    enum Verdict: String, Equatable, Sendable {
        case match
        case mismatch
        case unknown
    }

    let verdict: Verdict
    let host: String
    let configured: [String]
    let systemAnswer: [String]
    let publicAnswer: [String]
    let at: Date?

    static let unknown = ResolverIntegrityCheck(
        verdict: .unknown, host: "", configured: [], systemAnswer: [], publicAnswer: [], at: nil)

    var isMismatch: Bool { verdict == .mismatch }

    var detail: String {
        switch verdict {
        case .match:
            return String(localized: "The system resolver and the public resolver agree.")
        case .mismatch:
            return String(
                localized:
                    "The system resolver returned a different address than the public resolver for \(host). This is a warning: CDNs vary by resolver, but a hijack or a filtering DNS looks the same."
            )
        case .unknown:
            return String(localized: "Not enough answers to compare.")
        }
    }
}

enum ResolverIntegrity {
    static let canaryHost = "captive.apple.com"

    /// Both answers are sets of address strings; a single shared address counts
    /// as agreement because a round-robin record may return any subset.
    static func evaluate(
        configured: [String],
        systemAnswer: [String],
        publicAnswer: [String],
        host: String = canaryHost,
        at: Date? = nil
    ) -> ResolverIntegrityCheck {
        let system = normalizedSet(systemAnswer)
        let publicSet = normalizedSet(publicAnswer)
        guard !system.isEmpty, !publicSet.isEmpty else {
            return ResolverIntegrityCheck(
                verdict: .unknown, host: host, configured: configured, systemAnswer: systemAnswer,
                publicAnswer: publicAnswer, at: at)
        }
        let verdict: ResolverIntegrityCheck.Verdict =
            system.isDisjoint(with: publicSet) ? .mismatch : .match
        return ResolverIntegrityCheck(
            verdict: verdict, host: host, configured: configured, systemAnswer: systemAnswer,
            publicAnswer: publicAnswer, at: at)
    }

    private static func normalizedSet(_ addresses: [String]) -> Set<String> {
        Set(
            addresses
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
    }
}
