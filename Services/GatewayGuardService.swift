import Foundation
import LanFiCore
import SystemConfiguration

/// P3.7 — gateway ARP and DNS answer integrity.
///
/// Every two minutes it re-reads the default gateway and its ARP entry; every
/// ten minutes it compares what the system resolver answered for a canary host
/// with what Cloudflare returns directly. Both findings become Monitor events,
/// so the existing alert rules, quiet hours and Security Watch screen apply.
@MainActor
final class GatewayGuard: PollingGuard {
    static let shared = GatewayGuard()

    static let sampleInterval: TimeInterval = 120
    static let dnsInterval: TimeInterval = 600

    @Published private(set) var gatewayIP: String?
    @Published private(set) var gatewayMAC: String?
    @Published private(set) var resolverCheck: ResolverIntegrityCheck = .unknown
    @Published private(set) var macChangeCount = 0

    private var watch = GatewayARPWatch()
    private var lastDNSCheckAt: Date?
    private var lastMismatchSignature: String?

    private init() {
        super.init(interval: Self.sampleInterval)
    }

    override var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.gatewayGuard
    }

    // MARK: - Sampling

    override func performSample() async {
        let gateway = Self.defaultGateway()
        let entries = await Self.arpEntries()
        let change = watch.observe(gateway: gateway, entries: entries)
        gatewayIP = watch.gatewayIP
        gatewayMAC = watch.gatewayMAC
        macChangeCount = watch.changeCount

        if let change, change.isSuspicious {
            SecurityEvent.post(
                .gatewayChanged, subject: watch.gatewayIP ?? gateway ?? "gateway",
                detail: change.detail)
        }

        if let last = lastDNSCheckAt, Date().timeIntervalSince(last) < Self.dnsInterval { return }
        lastDNSCheckAt = Date()
        await checkResolver()
    }

    private func checkResolver() async {
        let host = ResolverIntegrity.canaryHost
        let configured = Self.configuredResolvers()
        async let systemAnswer = Self.resolve(host: host)
        async let publicAnswer = Self.resolvePublic(host: host)
        let check = ResolverIntegrity.evaluate(
            configured: configured, systemAnswer: await systemAnswer,
            publicAnswer: await publicAnswer, host: host, at: Date())
        resolverCheck = check

        guard check.verdict == .mismatch else {
            lastMismatchSignature = nil
            return
        }
        let signature = check.systemAnswer.sorted().joined(separator: ",")
        guard signature != lastMismatchSignature else { return }
        lastMismatchSignature = signature
        SecurityEvent.post(.dnsMismatch, subject: "DNS", detail: check.detail)
    }

    // MARK: - System reads

    private static func defaultGateway() -> String? {
        guard
            let store = SCDynamicStoreCreate(
                nil, "LanFi.GatewayGuard" as CFString, nil, nil),
            let raw = SCDynamicStoreCopyValue(
                store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return raw["Router"] as? String
    }

    private static func configuredResolvers() -> [String] {
        guard
            let store = SCDynamicStoreCreate(
                nil, "LanFi.GatewayGuard.DNS" as CFString, nil, nil),
            let raw = SCDynamicStoreCopyValue(
                store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
            let servers = raw["ServerAddresses"] as? [String]
        else { return [] }
        return servers
    }

    private static func arpEntries() async -> [ARPEntry] {
        ARPParser.parse(await ShellOutput.run("/usr/sbin/arp", ["-an"]))
    }

    /// The addresses macOS itself returns, i.e. through the configured resolver.
    private static func resolve(host: String) async -> [String] {
        await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            hints.ai_protocol = IPPROTO_TCP

            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, "443", &hints, &result) == 0, let first = result else {
                return []
            }
            defer { freeaddrinfo(result) }

            var addresses: [String] = []
            var pointer: UnsafeMutablePointer<addrinfo>? = first
            while let current = pointer {
                if let address = current.pointee.ai_addr {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let length = socklen_t(address.pointee.sa_len)
                    if getnameinfo(
                        address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
                        == 0
                    {
                        let value = String(cString: buffer)
                        if !addresses.contains(value) { addresses.append(value) }
                    }
                }
                pointer = current.pointee.ai_next
            }
            return addresses
        }.value
    }

    /// The same name asked straight to Cloudflare, bypassing the local resolver.
    private static func resolvePublic(host: String) async -> [String] {
        guard
            let answer = try? await UDPDNSClient().lookup(
                host: host, type: .a, resolver: .cloudflare, timeout: 4)
        else { return [] }
        return answer.records.filter { $0.type == .a }.map(\.value)
    }
}
