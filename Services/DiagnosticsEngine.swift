import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

// MARK: - Snapshot

enum DiagnosticsSystem {
    static func snapshot() -> LinkSnapshot {
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else {
            return .empty
        }

        let ssid = interface.ssid()
        let bssid = interface.bssid()?.uppercased()
        let rssi = Int(interface.rssiValue())
        let noiseValue = Int(interface.noiseMeasurement())
        let noise = noiseValue == 0 ? nil : noiseValue
        let snr = noise.map { rssi - $0 }
        let channel = interface.wlanChannel()
        let addresses = addressSnapshots()
        let routes = systemRoutes()

        return LinkSnapshot(
            interfaceName: interface.interfaceName,
            ssid: ssid,
            bssid: bssid,
            powerOn: interface.powerOn(),
            serviceActive: interface.serviceActive(),
            rssi: rssi == 0 ? nil : rssi,
            noise: noise,
            snr: snr,
            transmitRateMbps: interface.transmitRate(),
            channel: channel?.channelNumber,
            band: bandLabel(channel?.channelBand),
            widthMHz: widthMHz(channel?.channelWidth),
            security: securityLabel(interface.security()),
            ipv4Addresses: addresses.ipv4,
            ipv6Addresses: addresses.ipv6,
            router: routes.router,
            dnsServers: routes.dns
        )
    }

    private static func bandLabel(_ band: CWChannelBand?) -> String? {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        case .band6GHz: return "6 GHz"
        default: return nil
        }
    }

    private static func securityLabel(_ security: CWSecurity) -> String {
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .dynamicWEP: return "Dynamic WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpaEnterprise: return "WPA Enterprise"
        case .wpa2Personal: return "WPA2 Personal"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        case .wpa3Transition: return "WPA3 Transition"
        case .OWE: return "OWE"
        case .oweTransition: return "OWE Transition"
        default: return "Unknown"
        }
    }

    private static func widthMHz(_ width: CWChannelWidth?) -> Int? {
        switch width {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return nil
        }
    }

    private static func addressSnapshots() -> (ipv4: [String], ipv6: [String]) {
        var ipv4: [String] = []
        var ipv6: [String] = []
        var addressPointer: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addressPointer) == 0, let first = addressPointer else {
            return (ipv4, ipv6)
        }
        defer { freeifaddrs(first) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            guard let address = interface.ifa_addr else {
                pointer = interface.ifa_next
                continue
            }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else {
                pointer = interface.ifa_next
                continue
            }
            let name = String(cString: interface.ifa_name)
            if name == "lo0" || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") {
                pointer = interface.ifa_next
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            if getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let value = String(cString: host)
                if family == UInt8(AF_INET) {
                    if !ipv4.contains(value) { ipv4.append(value) }
                } else if !ipv6.contains(value) {
                    ipv6.append(value)
                }
            }
            pointer = interface.ifa_next
        }
        return (ipv4, ipv6)
    }

    private static func systemRoutes() -> (router: String?, dns: [String]) {
        guard let store = SCDynamicStoreCreate(nil, "LanFi.Diagnostics" as CFString, nil, nil) else {
            return (nil, [])
        }

        func value(_ key: String) -> [String: Any]? {
            guard let raw = SCDynamicStoreCopyValue(store, key as CFString) else { return nil }
            return raw as? [String: Any]
        }

        let ipv4 = value("State:/Network/Global/IPv4")
        let dns = value("State:/Network/Global/DNS")
        return (
            ipv4?["Router"] as? String,
            dns?["ServerAddresses"] as? [String] ?? []
        )
    }
}

// MARK: - Transport

struct PingResultSummary: Equatable {
    let result: PingResult
}

protocol DiagnosticsTransport {
    func ping(host: String, count: Int) async -> PingResult?
    func resolve(host: String) async -> DNSResult?
    func httpCheck(url: URL) async -> HTTPResult?
}

struct SystemDiagnosticsTransport: DiagnosticsTransport {
    func ping(host: String, count: Int) async -> PingResult? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.isExecutableFile(atPath: "/sbin/ping") else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "\(max(1, count))", "-n", "-q", "-W", "1000", host]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return PingOutputParser.parse(String(decoding: data, as: UTF8.self))
            } catch {
                return nil
            }
        }.value
    }

    func resolve(host: String) async -> DNSResult? {
        await Task.detached(priority: .utility) {
            let start = Date()
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            hints.ai_protocol = IPPROTO_TCP

            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, "443", &hints, &result)
            defer { if let result { freeaddrinfo(result) } }
            guard status == 0, let first = result else { return nil }

            var addresses: [String] = []
            var pointer: UnsafeMutablePointer<addrinfo>? = first
            while let current = pointer {
                if let address = current.pointee.ai_addr {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let length = socklen_t(address.pointee.sa_len)
                    if getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let value = String(cString: buffer)
                        if !addresses.contains(value) { addresses.append(value) }
                    }
                }
                pointer = current.pointee.ai_next
            }

            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            guard !addresses.isEmpty else { return nil }
            return DNSResult(host: host, addresses: addresses, milliseconds: milliseconds)
        }.value
    }

    func httpCheck(url: URL) async -> HTTPResult? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            return HTTPResult(
                statusCode: http?.statusCode ?? 0,
                finalURL: http?.url,
                bodyPrefix: String(decoding: data.prefix(256), as: UTF8.self),
                milliseconds: milliseconds
            )
        } catch {
            return nil
        }
    }
}

// MARK: - Engine

struct NetworkDiagnosticsEngine {
    let transport: DiagnosticsTransport
    let snapshotProvider: () -> LinkSnapshot
    let gatewayTimeoutMilliseconds: Int
    let publicHost: String

    init(
        transport: DiagnosticsTransport = SystemDiagnosticsTransport(),
        snapshotProvider: @escaping () -> LinkSnapshot = DiagnosticsSystem.snapshot,
        gatewayTimeoutMilliseconds: Int = 3000,
        publicHost: String = "1.1.1.1"
    ) {
        self.transport = transport
        self.snapshotProvider = snapshotProvider
        self.gatewayTimeoutMilliseconds = gatewayTimeoutMilliseconds
        self.publicHost = publicHost
    }

    func run() async -> DiagnosticsReport {
        let startedAt = Date()
        let snapshot = snapshotProvider()
        let startedMilliseconds = Self.monotonicMilliseconds()

        let router = snapshot.router
        let gatewayTask = Task { () -> PingResult? in
            guard let router else { return nil }
            return await transport.ping(host: router, count: 3)
        }
        let dnsTask = Task { await transport.resolve(host: "captive.apple.com") }
        let httpTask = Task {
            await transport.httpCheck(url: URL(string: "https://captive.apple.com/hotspot-detect.html")!)
        }
        let latencyTask = Task { await transport.ping(host: publicHost, count: 4) }

        let gateway = await gatewayTask.value
        let dns = await dnsTask.value
        let http = await httpTask.value
        let latency = await latencyTask.value
        let elapsed = max(0, Self.monotonicMilliseconds() - startedMilliseconds)

        var checks: [DiagnosticCheck] = []

        checks.append(
            check(
                id: "wifi-interface",
                title: "Wi-Fi interface",
                category: .link,
                status: snapshot.interfaceName == nil ? .fail : (snapshot.powerOn ? .pass : .fail),
                value: snapshot.interfaceName ?? "No interface",
                detail: snapshot.powerOn ? "Radio is powered on" : "Wi-Fi radio is off or unavailable"
            )
        )

        checks.append(
            check(
                id: "wifi-link",
                title: "Link state",
                category: .link,
                status: snapshot.isConnected ? .pass : .fail,
                value: snapshot.isConnected ? (snapshot.ssid ?? snapshot.bssid ?? "Connected") : "Not connected",
                detail: snapshot.bssid.map { "BSSID \($0)" } ?? "No active association"
            )
        )

        if let rssi = snapshot.rssi {
            checks.append(
                check(
                    id: "wifi-signal",
                    title: "Signal strength",
                    category: .link,
                    status: DiagnosticScoring.signalStatus(rssi: rssi),
                    value: "\(rssi) dBm",
                    detail: snapshot.snr.map { "SNR \($0) dB" } ?? "Noise floor unavailable"
                )
            )
        } else {
            checks.append(
                check(
                    id: "wifi-signal",
                    title: "Signal strength",
                    category: .link,
                    status: .warning,
                    value: "Unavailable",
                    detail: "Location permission may be required to read RSSI"
                )
            )
        }

        if let snr = snapshot.snr {
            checks.append(
                check(
                    id: "wifi-snr",
                    title: "SNR headroom",
                    category: .link,
                    status: snr >= 25 ? .pass : (snr >= 15 ? .warning : .fail),
                    value: "\(snr) dB",
                    detail:
                        "RSSI \(snapshot.rssi.map(String.init) ?? "—") dBm · noise \(snapshot.noise.map(String.init) ?? "—") dBm",
                    recommendation: snr < 25
                        ? "Move closer to the AP, switch to a less congested channel, or use 5/6 GHz."
                        : nil
                )
            )
        }

        checks.append(
            check(
                id: "ipv6",
                title: "IPv6 address",
                category: .network,
                status: snapshot.ipv6Addresses.isEmpty ? .warning : .pass,
                value: snapshot.ipv6Addresses.first ?? "No IPv6 address",
                detail: snapshot.ipv6Addresses.isEmpty
                    ? "The interface has no IPv6 address; IPv4-only connectivity may be intentional."
                    : "\(snapshot.ipv6Addresses.count) IPv6 address(es) configured",
                recommendation: snapshot.ipv6Addresses.isEmpty
                    ? "Enable IPv6 on the router or interface if the network is expected to provide it."
                    : nil
            )
        )

        checks.append(
            check(
                id: "wifi-security",
                title: "Security mode",
                category: .security,
                status: DiagnosticScoring.securityStatus(snapshot.security),
                value: snapshot.security ?? "Unknown",
                detail: securityDetail(snapshot.security),
                recommendation: DiagnosticScoring.securityStatus(snapshot.security) == .pass
                    ? nil : "Use WPA3 (or WPA2/WPA3 transition) with PMF where supported."
            )
        )

        checks.append(
            check(
                id: "ipv4",
                title: "IPv4 address",
                category: .network,
                status: snapshot.primaryIPv4 == nil ? .fail : .pass,
                value: snapshot.primaryIPv4 ?? "No address",
                detail: snapshot.ipv6Addresses.isEmpty
                    ? "No IPv6 address" : "IPv6: \(snapshot.ipv6Addresses.prefix(2).joined(separator: ", "))"
            )
        )

        checks.append(
            check(
                id: "gateway",
                title: "Default gateway",
                category: .network,
                status: gateway == nil ? .warning : DiagnosticScoring.latencyStatus(gateway),
                value: router ?? "Not found",
                detail: gatewayDetail(gateway, router: router),
                recommendation: gateway == nil
                    ? "Check the default route and the router's LAN interface." : nil
            )
        )

        checks.append(
            check(
                id: "dns",
                title: "DNS resolution",
                category: .dns,
                status: dns == nil ? .fail : (dns!.milliseconds > 800 ? .warning : .pass),
                value: dns?.addresses.first ?? "Resolution failed",
                detail: dns.map { "\($0.milliseconds) ms · \($0.addresses.count) address(es)" }
                    ?? "captive.apple.com did not resolve",
                recommendation: dns == nil
                    ? "Check DNS server configuration and try a public resolver." : nil
            )
        )

        let internetStatus: DiagnosticStatus
        if let http {
            if http.statusCode == 200, http.bodyPrefix.contains("Success") {
                internetStatus = .pass
            } else if http.statusCode > 0 {
                internetStatus = .warning
            } else {
                internetStatus = .fail
            }
        } else {
            internetStatus = .fail
        }
        checks.append(
            check(
                id: "internet",
                title: "Internet / captive portal",
                category: .internet,
                status: internetStatus,
                value: http.map { "HTTP \($0.statusCode)" } ?? "No response",
                detail: http.map { "\($0.milliseconds) ms · \($0.finalURL?.host ?? "captive.apple.com")" }
                    ?? "HTTPS check did not complete"
            )
        )

        checks.append(
            check(
                id: "latency",
                title: "Public latency",
                category: .performance,
                status: latency == nil ? .fail : DiagnosticScoring.latencyStatus(latency),
                value: latency?.averageMilliseconds.map { String(format: "%.0f ms", $0) } ?? "Unreachable",
                detail: latency.map {
                    "loss \(String(format: "%.0f", $0.packetLossPercent))% · jitter \(String(format: "%.1f", $0.standardDeviationMilliseconds ?? 0)) ms"
                } ?? "\(publicHost) did not respond",
                recommendation: latency == nil || (latency?.packetLossPercent ?? 0) > 0
                    ? "Check the WAN link, router load and Wi-Fi retries; packet loss is not normal." : nil
            )
        )

        if snapshot.dnsServers.isEmpty {
            checks.append(
                check(
                    id: "dns-servers",
                    title: "Configured DNS servers",
                    category: .dns,
                    status: .warning,
                    value: "None",
                    detail: "macOS did not report a DNS server"
                )
            )
        }

        checks.append(
            check(
                id: "duration",
                title: "Diagnostic run",
                category: .performance,
                status: .pass,
                value: "\(elapsed) ms",
                detail: "Wi-Fi link, gateway, DNS, HTTPS and latency"
            )
        )

        return DiagnosticsReport(
            id: UUID().uuidString,
            startedAt: startedAt,
            finishedAt: Date(),
            snapshot: snapshot,
            checks: checks
        )
    }

    private func check(
        id: String,
        title: String,
        category: DiagnosticCategory,
        status: DiagnosticStatus,
        value: String,
        detail: String,
        recommendation: String? = nil
    ) -> DiagnosticCheck {
        DiagnosticCheck(
            id: id,
            title: title,
            category: category,
            status: status,
            value: value,
            detail: detail,
            durationMilliseconds: nil,
            recommendation: recommendation
        )
    }

    private func gatewayDetail(_ ping: PingResult?, router: String?) -> String {
        guard router != nil else { return "No default route" }
        guard let ping else { return "Gateway did not answer ICMP" }
        return
            "\(String(format: "%.0f", ping.averageMilliseconds ?? 0)) ms · loss \(String(format: "%.0f", ping.packetLossPercent))%"
    }

    private func securityDetail(_ security: String?) -> String {
        guard let security else { return "Security mode unavailable" }
        let lower = security.lowercased()
        if lower.contains("open") { return "Open network — traffic is unencrypted" }
        if lower.contains("wep") { return "WEP is cryptographically broken" }
        if lower.contains("wpa3") || lower.contains("owe") { return "Modern security" }
        if lower.contains("wpa2") { return "WPA2 — acceptable, WPA3 preferred" }
        return "Legacy or unknown security"
    }

    private static func monotonicMilliseconds() -> Int {
        Int(ProcessInfo.processInfo.systemUptime * 1000)
    }
}

enum DiagnosticScoring {
    static func signalStatus(rssi: Int) -> DiagnosticStatus {
        if rssi >= -60 { return .pass }
        if rssi >= -75 { return .warning }
        return .fail
    }

    static func securityStatus(_ security: String?) -> DiagnosticStatus {
        guard let security else { return .warning }
        let lower = security.lowercased()
        if lower.contains("open") || lower.contains("wep") { return .fail }
        if lower.contains("wpa ") || lower.contains("wpa2") { return .warning }
        return .pass
    }

    static func latencyStatus(_ ping: PingResult?) -> DiagnosticStatus {
        guard let ping else { return .fail }
        if ping.packetLossPercent > 10 { return .fail }
        guard let average = ping.averageMilliseconds else { return .fail }
        if average > 150 { return .fail }
        if average > 80 || (ping.standardDeviationMilliseconds ?? 0) > 30 { return .warning }
        return .pass
    }

    static func overall(_ checks: [DiagnosticCheck]) -> DiagnosticStatus {
        if checks.contains(where: { $0.status == .fail }) { return .fail }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        return .pass
    }
}
