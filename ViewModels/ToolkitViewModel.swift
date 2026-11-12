import Foundation
import SwiftUI

@MainActor
final class ToolkitViewModel: ObservableObject {
    @Published var selection: ToolboxTool = .wifiAnalyzer {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey) }
    }

    private static let selectionKey = "LanFi.toolkit.selection"

    let ping = PingToolModel()
    let dns = DNSToolModel()
    let dnsPropagation = DNSPropagationToolModel()
    let whois = WhoisToolModel()
    let geoIP = GeoIPToolModel()
    let portScan = PortScanToolModel()
    let traceroute = TracerouteToolModel()
    let mtr = MTRToolModel()
    let visualTraceroute = VisualTracerouteToolModel()
    let ssl = SSLToolModel()
    let subnet = SubnetToolModel()
    let pathCheck = PathCheckToolModel()
    let lanScanner = LANScannerToolModel()
    let iperf3 = Iperf3ToolModel()
    let speedTest = SpeedTestToolModel()

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.selectionKey) {
            // 5.0.1 removed the duplicate "Wi-Fi Networks" item; it opened the
            // same screen as the analyzer, so old selections map onto it.
            let migrated = raw == "wifiNetworks" ? ToolboxTool.wifiAnalyzer.rawValue : raw
            if let stored = ToolboxTool(rawValue: migrated), stored.isAvailable {
                selection = stored
            }
        }
    }

    func select(_ tool: ToolboxTool) {
        guard tool.isAvailable else { return }
        selection = tool
    }
}

// MARK: - Ping

@MainActor
final class PingToolModel: ObservableObject {
    @Published var host = "1.1.1.1"
    @Published var transport: PingTransport = .icmp
    @Published var count = 10
    @Published var continuous = false
    @Published var interval = 0.5
    @Published var portText = "443"
    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var statistics: PingStatistics? {
        samples.isEmpty ? nil : PingStatistics(host: host, samples: samples)
    }

    var port: UInt16? { UInt16(portText) }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host, defaultPort: 443) else {
            errorMessage = "Enter a host name or address."
            return
        }
        guard transport == .icmp || (port ?? 0) > 0 else {
            errorMessage = "Enter a TCP port between 1 and 65535."
            return
        }
        errorMessage = nil
        samples = []
        isRunning = true

        let probe: any PingProbing =
            transport == .icmp ? ICMPPingProbe() : TCPPingProbe(port: port ?? 443)
        let service = PingService(probe: probe)
        let total = continuous ? 10_000 : count
        let delay = interval
        task = Task { [weak self] in
            guard let self else { return }
            for await sample in service.stream(
                host: target.host, count: total, interval: delay)
            {
                self.samples.append(sample)
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        samples = []
        errorMessage = nil
    }
}

// MARK: - DNS

@MainActor
final class DNSToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var tab: DNSLookupTab = .records
    @Published var type: DNSRecordType = .a
    @Published var resolverChoice = "cloudflare"
    @Published var customResolver = "1.1.1.1"
    @Published private(set) var result: DNSLookupResult?
    @Published private(set) var mailReport: DNSMailReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var resolver: DNSResolver {
        switch resolverChoice {
        case "system": return .system
        case "google": return .google
        case "custom":
            return DNSResolver.custom(customResolver) ?? .system
        default: return .cloudflare
        }
    }

    func run() {
        switch tab {
        case .records: runRecords()
        case .mail, .reports: runMail()
        }
    }

    private func runRecords() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        if resolverChoice == "custom", DNSResolver.custom(customResolver) == nil {
            errorMessage = "Enter a resolver address, for example 1.1.1.1."
            return
        }
        errorMessage = nil
        result = nil
        isRunning = true
        let selectedType = type
        let selectedResolver = resolver
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let lookup = try await UDPDNSClient().lookup(
                    host: target.host, type: selectedType, resolver: selectedResolver)
                self.result = lookup
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    private func runMail() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        if resolverChoice == "custom", DNSResolver.custom(customResolver) == nil {
            errorMessage = "Enter a resolver address, for example 1.1.1.1."
            return
        }
        errorMessage = nil
        mailReport = nil
        isRunning = true
        let selectedResolver = resolver
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isRunning = false
                self.task = nil
            }
            let report = await DNSMailLookupService().lookup(
                domain: target.host, resolver: selectedResolver)
            if Task.isCancelled { return }
            self.mailReport = report
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        result = nil
        mailReport = nil
        errorMessage = nil
        isRunning = false
    }
}

// MARK: - Visual traceroute

@MainActor
final class VisualTracerouteToolModel: ObservableObject {
    enum Phase: Equatable {
        case idle, tracing, locating
    }

    @Published var host = "example.com"
    @Published var maxHops = 20
    @Published private(set) var hops: [VisualTracerouteHop] = []
    @Published private(set) var phase: Phase = .idle
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var isRunning: Bool { phase != .idle }
    var mappedCount: Int { hops.filter { $0.geo != nil }.count }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        errorMessage = nil
        hops = []
        phase = .tracing
        let limit = maxHops
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let report = try await SystemTracerouteRunner().trace(
                    host: target.host, maxHops: limit, waitSeconds: 2)
                if Task.isCancelled { return }
                self.hops = report.hops.map { VisualTracerouteHop(hop: $0, geo: nil) }
                self.phase = .locating
                for index in self.hops.indices {
                    if Task.isCancelled { return }
                    guard let address = self.hops[index].hop.address,
                        VisualTracerouteFilter.isPublic(address)
                    else { continue }
                    var geo = try? await GeoIPClient().lookup(address)
                    if geo == nil {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        geo = try? await GeoIPClient().lookup(address)
                    }
                    if let geo {
                        if Task.isCancelled { return }
                        self.hops[index] = VisualTracerouteHop(
                            hop: self.hops[index].hop, geo: geo)
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                self.phase = .idle
                self.task = nil
            } catch is CancellationError {
                self.phase = .idle
                self.task = nil
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .idle
                self.task = nil
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func clear() {
        stop()
        hops = []
        errorMessage = nil
    }
}

// MARK: - DNS propagation

@MainActor
final class DNSPropagationToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var type: DNSRecordType = .a
    @Published var expected = ""
    @Published private(set) var results: [DNSPropagationResult] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var summary: DNSPropagationSummary {
        DNSPropagationSummary(expected: expected, results: results)
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a domain name, for example example.com."
            return
        }
        errorMessage = nil
        results = []
        isRunning = true
        let selectedType = type
        let resolvers = DNSResolver.propagation
        task = Task { [weak self] in
            guard let self else { return }
            let collected = await withTaskGroup(of: DNSPropagationResult.self) { group in
                for resolver in resolvers {
                    group.addTask {
                        do {
                            let lookup = try await UDPDNSClient().lookup(
                                host: target.host,
                                type: selectedType,
                                resolver: resolver,
                                timeout: 4
                            )
                            return DNSPropagationResult(
                                resolver: resolver,
                                records: lookup.records,
                                milliseconds: lookup.milliseconds,
                                error: nil
                            )
                        } catch {
                            return DNSPropagationResult(
                                resolver: resolver,
                                records: [],
                                milliseconds: 0,
                                error: error.localizedDescription
                            )
                        }
                    }
                }
                var values: [DNSPropagationResult] = []
                for await result in group { values.append(result) }
                return values
            }
            if Task.isCancelled { return }
            let order = Dictionary(
                uniqueKeysWithValues: resolvers.enumerated().map { ($1.id, $0) })
            self.results = collected.sorted {
                order[$0.resolver.id, default: 99] < order[$1.resolver.id, default: 99]
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        results = []
        errorMessage = nil
    }
}

// MARK: - Whois

@MainActor
final class WhoisToolModel: ObservableObject {
    @Published var query = "example.com"
    @Published private(set) var report: WhoisReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        let target = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            errorMessage = "Enter a domain or IP address."
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await WhoisClient().lookup(target)
                if Task.isCancelled { return }
                self.report = result
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        report = nil
        errorMessage = nil
        isRunning = false
    }
}

// MARK: - GeoIP

@MainActor
final class GeoIPToolModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var report: GeoIPReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run(myIP: Bool = false) {
        guard !isRunning else { return }
        let target = myIP ? nil : query
        errorMessage = nil
        report = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await GeoIPClient().lookup(target)
                if Task.isCancelled { return }
                self.report = result
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        report = nil
        errorMessage = nil
        isRunning = false
    }
}

// MARK: - Port scan

@MainActor
final class PortScanToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var portSpec = PortPreset.common.ports.map(String.init).joined(separator: ",")
    @Published var timeout = 1.5
    @Published var concurrency = 24
    @Published private(set) var results: [PortScanResult] = []
    @Published private(set) var udpResults: [PortScanResult] = []
    @Published private(set) var isRunning = false
    @Published var detectServices = true
    @Published var includeUDP = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var openCount: Int { results.filter { $0.state == .open }.count }
    var closedCount: Int { results.filter { $0.state == .closed }.count }
    var filteredCount: Int { results.filter { $0.state == .filtered }.count }

    func applyPreset(_ preset: PortPreset) {
        portSpec = preset.ports.map(String.init).joined(separator: ",")
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        let ports: [UInt16]
        do {
            ports = try PortSpec.parse(portSpec)
        } catch {
            errorMessage = Self.message(for: error)
            return
        }
        errorMessage = nil
        results = []
        isRunning = true
        let scanner = PortScanner(probe: TCPPortProbe())
        let timeout = timeout
        let concurrency = concurrency
        task = Task { [weak self] in
            guard let self else { return }
            var scan = await scanner.scan(
                host: target.host, ports: ports, timeout: timeout, concurrency: concurrency)
            if self.detectServices {
                let openPorts = scan.filter { $0.state == .open }.map(\.port)
                var banners: [UInt16: String] = [:]
                await withTaskGroup(of: (UInt16, String?).self) { group in
                    for port in openPorts {
                        group.addTask {
                            let banner = await ServiceBannerProbe().probe(
                                host: target.host, port: port)
                            return (port, banner)
                        }
                    }
                    for await (port, banner) in group {
                        if let banner { banners[port] = banner }
                    }
                }
                scan = scan.map { result in
                    guard let banner = banners[result.port] else { return result }
                    return PortScanResult(
                        port: result.port,
                        service: result.service,
                        state: result.state,
                        responseMilliseconds: result.responseMilliseconds,
                        detail: banner
                    )
                }
            }
            if Task.isCancelled {
                self.isRunning = false
                self.task = nil
                return
            }
            self.results = scan
            if self.includeUDP {
                let udpPorts: [UInt16] = [53, 67, 68, 69, 123, 137, 161, 500, 1900, 5353]
                let udp = await PortScanner(probe: UDPPortProbe()).scan(
                    host: target.host, ports: udpPorts, timeout: timeout,
                    concurrency: min(concurrency, 10))
                if !Task.isCancelled { self.udpResults = udp }
            } else {
                self.udpResults = []
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        results = []
        udpResults = []
        errorMessage = nil
    }

    private static func message(for error: Error) -> String {
        switch error {
        case PortSpecError.empty: return "Enter at least one port."
        case PortSpecError.invalid(let token): return "“\(token)” is not a valid port or range."
        case PortSpecError.outOfRange(let port): return "Port \(port) is outside 1–65535."
        case PortSpecError.tooMany(let limit): return "Scan at most \(limit) ports at once."
        default: return error.localizedDescription
        }
    }
}

// MARK: - Traceroute

@MainActor
final class TracerouteToolModel: ObservableObject {
    @Published var host = "1.1.1.1"
    @Published var maxHops = 30
    @Published var probes = 1
    @Published var waitSeconds = 2
    @Published var resolveNames = false
    @Published private(set) var result: TracerouteReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        errorMessage = nil
        result = nil
        isRunning = true
        let hops = maxHops
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let report = try await SystemTracerouteRunner().trace(
                    host: target.host, maxHops: hops, waitSeconds: self.waitSeconds,
                    probes: self.probes, resolveNames: self.resolveNames)
                if Task.isCancelled { return }
                self.result = report
            } catch is CancellationError {
                // Cancelled by the user; leave the partial state empty.
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        result = nil
        errorMessage = nil
    }
}

// MARK: - MTR

@MainActor
final class MTRToolModel: ObservableObject {
    @Published var host = "1.1.1.1"
    @Published var rounds = 10
    @Published var maxHops = 20
    @Published var continuous = false
    @Published private(set) var report: MTRReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        let totalRounds = rounds
        let hops = maxHops
        let service = MTRService(runner: SystemTracerouteRunner())
        task = Task { [weak self] in
            guard let self else { return }
            repeat {
                do {
                    let result = try await service.run(
                        host: target.host, rounds: totalRounds, maxHops: hops, waitSeconds: 1
                    ) { update in
                        Task { @MainActor [weak self] in
                            self?.report = update
                        }
                    }
                    if Task.isCancelled { break }
                    self.report = result
                } catch is CancellationError {
                    break
                } catch {
                    self.errorMessage = error.localizedDescription
                    break
                }
                if !self.continuous { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } while self.continuous && !Task.isCancelled
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        report = nil
        errorMessage = nil
    }
}

// MARK: - TLS

@MainActor
final class SSLToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var portText = "443"
    @Published private(set) var report: TLSCertificateReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host), let port = UInt16(portText), port > 0 else {
            errorMessage = "Enter a host and a port between 1 and 65535."
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let inspected = try await URLSessionTLSCertificateInspector().inspect(
                    host: target.host, port: port)
                self.report = inspected
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        report = nil
        errorMessage = nil
        isRunning = false
    }
}

// MARK: - Subnet

@MainActor
final class SubnetToolModel: ObservableObject {
    @Published var input = "192.168.1.0/24"
    @Published private(set) var result: SubnetInfo?
    @Published var errorMessage: String?

    func calculate() {
        if let subnet = SubnetCalculator.parse(input) {
            result = subnet
            errorMessage = nil
        } else {
            result = nil
            errorMessage =
                "Enter a valid IPv4 CIDR or address + netmask, for example 192.168.1.10/24."
        }
    }

    func useCurrentNetwork() {
        let report = SystemInterfaceScanner.scan()
        guard
            let interface = report.interfaces.first(where: \.isPrimary),
            let ipv4 = interface.ipv4.first,
            let prefix = ipv4.prefixLength
        else {
            errorMessage = "Could not determine this Mac's IPv4 network."
            return
        }
        input = "\(ipv4.address)/\(prefix)"
        calculate()
    }
}

// MARK: - Path check

@MainActor
final class PathCheckToolModel: ObservableObject {
    @Published var host = "example.com"
    @Published var portsText = "80,443"
    @Published private(set) var results: [PathCheckResult] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var reachableCount: Int { results.filter { $0.isOpen }.count }

    func applyPreset(_ preset: PortPreset) {
        portsText = preset.ports.map(String.init).joined(separator: ",")
    }

    func run() {
        guard !isRunning else { return }
        guard let parsed = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        let ports: [UInt16]
        do {
            var parsedPorts = try PortSpec.parse(portsText)
            if let port = parsed.port { parsedPorts.append(port) }
            ports = Array(Set(parsedPorts)).sorted().prefix(32).map { $0 }
        } catch {
            errorMessage = "Enter ports like 80,443 or 1-1024."
            return
        }
        guard !ports.isEmpty else {
            errorMessage = "Enter at least one port."
            return
        }
        errorMessage = nil
        results = []
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            let collected = await withTaskGroup(of: PathCheckResult.self) { group in
                for port in ports {
                    group.addTask {
                        let outcome = await TCPProbe.connect(
                            host: parsed.host, port: port, timeout: 4)
                        return PathCheckResult(port: port, outcome: outcome)
                    }
                }
                var values: [PathCheckResult] = []
                for await result in group { values.append(result) }
                return values.sorted { $0.port < $1.port }
            }
            if Task.isCancelled { return }
            self.results = collected
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        results = []
        errorMessage = nil
    }
}

// MARK: - iperf3

@MainActor
final class Iperf3ToolModel: ObservableObject {
    @Published var host = "192.168.1.10"
    @Published var portText = "5201"
    @Published var duration = 10
    @Published var direction: Iperf3Direction = .upload
    @Published private(set) var report: Iperf3Report?
    @Published private(set) var isRunning = false
    @Published private(set) var savedServers: [Iperf3Server] = []
    @Published private(set) var history: [Iperf3Measurement] = []
    @Published var errorMessage: String?

    private let historyStore = Iperf3HistoryStore()
    private let serversKey = "LanFi.iperf3.servers"
    private var task: Task<Void, Never>?

    var isInstalled: Bool { Iperf3Runner.locate() != nil }
    var newestFirst: [Iperf3Measurement] { Array(history.reversed()) }

    init() {
        history = (try? historyStore.load()) ?? []
        if let data = UserDefaults.standard.data(forKey: serversKey),
            let servers = try? JSONDecoder().decode([Iperf3Server].self, from: data)
        {
            savedServers = servers
        }
    }

    func saveCurrentServer() {
        guard let parsed = ToolTarget.parse(host), let port = UInt16(portText), port > 0
        else { return }
        savedServers.removeAll { $0.host == parsed.host && $0.port == port }
        savedServers.insert(
            Iperf3Server(name: parsed.host, host: parsed.host, port: port), at: 0)
        if savedServers.count > 12 { savedServers.removeLast(savedServers.count - 12) }
        persistServers()
    }

    func applyServer(_ server: Iperf3Server) {
        host = server.host
        portText = String(server.port)
    }

    func removeServer(_ server: Iperf3Server) {
        savedServers.removeAll { $0.id == server.id }
        persistServers()
    }

    func clearHistory() {
        history = []
        historyStore.clear()
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(savedServers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    private func record(_ report: Iperf3Report) {
        history.append(Iperf3Measurement(report: report))
        if history.count > 50 { history.removeFirst(history.count - 50) }
        try? historyStore.save(history)
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host), let port = UInt16(portText), port > 0 else {
            errorMessage = "Enter a host and a port between 1 and 65535."
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        let duration = duration
        let direction = direction
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let measured = try await Iperf3Runner().run(
                    host: target.host,
                    port: port,
                    durationSeconds: duration,
                    direction: direction
                )
                if Task.isCancelled { return }
                self.report = measured
                self.record(measured)
            } catch is CancellationError {
                // Keep whatever the user already has.
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        report = nil
        errorMessage = nil
    }
}

// MARK: - LAN scanner

@MainActor
final class LANScannerToolModel: ObservableObject {
    @Published private(set) var result: LANScanResult?
    @Published private(set) var isScanning = false
    @Published var errorMessage: String?
    @Published private(set) var newMACs: Set<String> = []
    @Published var guardEnabled: Bool {
        didSet {
            defaults.set(guardEnabled, forKey: Self.guardKey)
            if guardEnabled, let result {
                knownMACs.formUnion(result.devices.map { $0.mac ?? $0.ip })
                guardStore.save(knownMACs)
            } else if !guardEnabled {
                newMACs = []
            }
        }
    }

    private static let guardKey = "LanFi.lanGuardEnabled"
    private let defaults = UserDefaults.standard
    private let guardStore = LANGuardStore()
    private let notifier: any UserNotifying
    private var knownMACs: Set<String>
    private var task: Task<Void, Never>?

    init(notifier: any UserNotifying = SystemUserNotifier()) {
        self.notifier = notifier
        knownMACs = guardStore.load()
        guardEnabled = defaults.bool(forKey: Self.guardKey)
    }

    var devices: [LANDevice] { result?.devices ?? [] }

    var selectedSubnet: String { result?.subnet ?? String(localized: "Not scanned") }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        let known = knownMACs
        let guarding = guardEnabled
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let scan = try await LANScannerService().scan(
                    knownMACs: known, guardEnabled: guarding)
                if Task.isCancelled { return }
                self.result = scan
                self.applyGuard(scan)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isScanning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isScanning = false
    }

    func clear() {
        stop()
        result = nil
        newMACs = []
        errorMessage = nil
    }

    private func applyGuard(_ scan: LANScanResult) {
        guard guardEnabled else { return }
        let seen = Set(scan.devices.map { $0.mac ?? $0.ip })
        if knownMACs.isEmpty {
            knownMACs = seen
            guardStore.save(knownMACs)
            return
        }
        let new = seen.subtracting(knownMACs)
        newMACs = new
        if !new.isEmpty {
            let names = scan.devices
                .filter { device in new.contains(device.mac ?? device.ip) }
                .map(\.displayName)
                .prefix(3)
                .joined(separator: ", ")
            Task {
                await notifier.notify(
                    title: "New device on \(scan.subnet)", body: names)
            }
        }
        knownMACs.formUnion(seen)
        guardStore.save(knownMACs)
    }
}

// MARK: - Speed test

@MainActor
final class SpeedTestToolModel: ObservableObject {
    @Published private(set) var report: ThroughputReport?
    @Published private(set) var history: [ThroughputMeasurement] = []
    @Published var schedule: SpeedTestSchedule {
        didSet {
            defaults.set(schedule.rawValue, forKey: Self.scheduleKey)
            startScheduler()
        }
    }
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private static let scheduleKey = "LanFi.speedTestSchedule"
    private let historyStore = ThroughputHistoryStore()
    private let defaults = UserDefaults.standard
    private var task: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?

    init() {
        schedule =
            SpeedTestSchedule(rawValue: defaults.string(forKey: Self.scheduleKey) ?? "") ?? .off
        let loaded = historyStore.load()
        history = loaded
        report = loaded.last?.report
        startScheduler()
    }

    var nextRun: Date? {
        schedule.nextRun(after: history.last?.testedAt)
    }

    var newestFirst: [ThroughputMeasurement] {
        Array(history.reversed())
    }

    func run() {
        guard !isRunning else { return }
        task = Task { [weak self] in
            await self?.measure()
        }
    }

    func measure() async {
        guard !isRunning else { return }
        errorMessage = nil
        isRunning = true
        defer {
            isRunning = false
            task = nil
        }
        do {
            let measured = try await Task.detached(priority: .userInitiated) {
                try await ThroughputTester.run()
            }.value
            report = measured
            record(measured)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        report = nil
        errorMessage = nil
        isRunning = false
    }

    func clearHistory() {
        history.removeAll()
        historyStore.clear()
        report = nil
    }

    private func record(_ report: ThroughputReport) {
        history.append(ThroughputMeasurement(report: report))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
        historyStore.save(history)
    }

    private func startScheduler() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard schedule != .off else { return }
        scheduleTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !self.isRunning,
                    self.schedule.isDue(lastRun: self.history.last?.testedAt)
                {
                    self.run()
                }
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
            }
        }
    }
}
