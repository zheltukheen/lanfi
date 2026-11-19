import Foundation
import LanFiCore
import SystemConfiguration

extension Notification.Name {
    /// P3.7: the gateway guard posts findings here, and `MonitorViewModel`
    /// folds them into its event log. This keeps the guard independent of the
    /// monitor's lifetime.
    static let lanFiSecurityEvent = Notification.Name("LanFi.securityEvent")
}

/// P3.7 — gateway ARP and DNS answer integrity.
///
/// Every two minutes it re-reads the default gateway and its ARP entry; every
/// ten minutes it compares what the system resolver answered for a canary host
/// with what Cloudflare returns directly. Both findings become Monitor events,
/// so the existing alert rules, quiet hours and Security Watch screen apply.
@MainActor
final class GatewayGuard: ObservableObject {
    static let shared = GatewayGuard()

    static let sampleInterval: TimeInterval = 120
    static let dnsInterval: TimeInterval = 600

    @Published private(set) var gatewayIP: String?
    @Published private(set) var gatewayMAC: String?
    @Published private(set) var resolverCheck: ResolverIntegrityCheck = .unknown
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var macChangeCount = 0
    @Published private(set) var isSampling = false

    private var watch = GatewayARPWatch()
    private var timer: Timer?
    private var lastDNSCheckAt: Date?
    private var lastMismatchSignature: String?
    private var isSampleInFlight = false

    deinit {
        timer?.invalidate()
    }

    var isEnabled: Bool {
        AppSettingsStore.shared.settings.automation.gatewayGuard
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = Self.sampleInterval * 0.2
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

    // MARK: - Sampling

    private func sample() async {
        guard isEnabled, !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }

        let gateway = Self.defaultGateway()
        let entries = await Self.arpEntries()
        let change = watch.observe(gateway: gateway, entries: entries)
        gatewayIP = watch.gatewayIP
        gatewayMAC = watch.gatewayMAC
        macChangeCount = watch.changeCount
        lastCheckedAt = Date()

        if let change, change.isSuspicious {
            post(.gatewayChanged, subject: watch.gatewayIP ?? gateway ?? "gateway", detail: change.detail)
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
        post(.dnsMismatch, subject: "DNS", detail: check.detail)
    }

    private func post(_ kind: MonitorEventKind, subject: String, detail: String) {
        let event = MonitorEvent(
            at: Date(), kind: kind, bssid: "", ssid: subject, detail: detail)
        NotificationCenter.default.post(
            name: .lanFiSecurityEvent, object: nil, userInfo: ["event": event])
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
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
            process.arguments = ["-an"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return ARPParser.parse(String(decoding: data, as: UTF8.self))
        }.value
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
