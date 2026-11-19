import Foundation
import LanFiCore

/// P3.4 — polls the local route table and resolver configuration to show whether
/// a tunnel is up and whether DNS or IPv6 slips around it.
///
/// One poll every 20 s, all local, no provider API and no credentials. Drop and
/// leak findings are posted as Monitor events through the security channel.
@MainActor
final class VPNGuard: ObservableObject {
    static let shared = VPNGuard()
    static let pollInterval: TimeInterval = 20

    @Published private(set) var report: VPNGuardReport = .empty
    @Published private(set) var isSampling = false

    private var timer: Timer?
    private var lastSignature: String?
    private var announcedLeakSignature: String?
    private var isSampleInFlight = false

    deinit {
        timer?.invalidate()
    }

    var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.vpnGuard
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = Self.pollInterval * 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sampleNow() async {
        await sample()
    }

    private func sample() async {
        guard isEnabled, !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }

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
            post(
                .vpnDropped, subject: previous.vpn.interfaceLabel ?? "VPN",
                detail: String(localized: "The VPN tunnel went down unexpectedly."))
        }

        if updated.hasLeak, announcedLeakSignature != signature {
            announcedLeakSignature = signature
            let detail = [dns.status == .leak ? dns.detail : nil, ipv6.status == .leak ? ipv6.detail : nil]
                .compactMap { $0 }
                .joined(separator: " ")
            post(.vpnLeak, subject: vpn.interfaceLabel ?? "VPN", detail: detail)
        } else if !updated.hasLeak {
            announcedLeakSignature = nil
        }
    }

    private func post(_ kind: MonitorEventKind, subject: String, detail: String) {
        let event = MonitorEvent(
            at: Date(), kind: kind, bssid: "", ssid: subject, detail: detail)
        NotificationCenter.default.post(
            name: .lanFiSecurityEvent, object: nil, userInfo: ["event": event])
    }

    // MARK: - System reads

    private static func routeTable(family: String) async -> String {
        await run("/usr/sbin/netstat", ["-rn", "-f", family])
    }

    private static func scutilDNS() async -> String {
        await run("/usr/sbin/scutil", ["--dns"])
    }

    private static func run(_ path: String, _ arguments: [String]) async -> String {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
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
