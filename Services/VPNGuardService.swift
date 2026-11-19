import Foundation
import LanFiCore

/// P3.4 — polls the local route table and resolver configuration to show whether
/// a tunnel is up and whether DNS or IPv6 slips around it.
///
/// One poll every 20 s, all local, no provider API and no credentials. Drop and
/// leak findings are posted as Monitor events through the security channel.
@MainActor
final class VPNGuard: PollingGuard {
    static let shared = VPNGuard()
    static let pollInterval: TimeInterval = 20

    @Published private(set) var report: VPNGuardReport = .empty

    private var lastSignature: String?
    private var announcedLeakSignature: String?

    private init() {
        super.init(interval: Self.pollInterval)
    }

    override var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.vpnGuard
    }

    override func performSample() async {
        async let ipv4Routes = Self.routeTable(family: "inet")
        async let ipv6Routes = Self.routeTable(family: "inet6")
        async let dnsOutput = Self.scutilDNS()
        let tunnels = Self.upTunnelInterfaces()

        let vpn = VPNDetector.detect(
            defaultInterface: RouteTableOutput.defaultInterface(await ipv4Routes),
            activeTunnels: tunnels)
        let dns = VPNDNSIntegrity.evaluate(vpn: vpn, blocks: SCUtilDNSOutput.parse(await dnsOutput))
        let ipv6 = VPNIPv6Integrity.evaluate(
            vpn: vpn, ipv6DefaultInterface: RouteTableOutput.defaultInterface(await ipv6Routes))

        let previous = report
        let updated = VPNGuardReport(vpn: vpn, dns: dns, ipv6: ipv6, checkedAt: Date())
        report = updated

        let signature = updated.signature
        guard signature != lastSignature else { return }
        let wasUp = previous.vpn.isUp
        lastSignature = signature

        if wasUp, !vpn.isUp {
            SecurityEvent.post(
                .vpnDropped, subject: previous.vpn.interfaceLabel ?? "VPN",
                detail: String(localized: "The VPN tunnel went down unexpectedly."))
        }

        if updated.hasLeak, announcedLeakSignature != signature {
            announcedLeakSignature = signature
            let detail = [dns.status == .leak ? dns.detail : nil, ipv6.status == .leak ? ipv6.detail : nil]
                .compactMap { $0 }
                .joined(separator: " ")
            SecurityEvent.post(.vpnLeak, subject: vpn.interfaceLabel ?? "VPN", detail: detail)
        } else if !updated.hasLeak {
            announcedLeakSignature = nil
        }
    }

    // MARK: - System reads

    private static func routeTable(family: String) async -> String {
        await ShellOutput.run("/usr/sbin/netstat", ["-rn", "-f", family])
    }

    private static func scutilDNS() async -> String {
        await ShellOutput.run("/usr/sbin/scutil", ["--dns"])
    }

    private static func upTunnelInterfaces() -> [String] {
        var names: [String] = []
        var ifaddrsPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrsPointer) == 0, let first = ifaddrsPointer else { return names }
        defer { freeifaddrs(ifaddrsPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            if let name = entry.ifa_name.map({ String(cString: $0) }),
                entry.ifa_flags & UInt32(IFF_UP) != 0,
                TunnelInterface.isTunnel(name),
                !names.contains(name)
            {
                names.append(name)
            }
            pointer = entry.ifa_next
        }
        return names
    }
}
