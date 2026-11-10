import Foundation
import SwiftUI

@MainActor
final class ToolkitViewModel: ObservableObject {
    @Published var selection: ToolboxTool = .wifiAnalyzer

    let ping = PingToolModel()
    let dns = DNSToolModel()
    let portScan = PortScanToolModel()
    let traceroute = TracerouteToolModel()
    let mtr = MTRToolModel()
    let ssl = SSLToolModel()
    let subnet = SubnetToolModel()
    let pathCheck = PathCheckToolModel()
    let lanScanner = LANScannerToolModel()
    let iperf3 = Iperf3ToolModel()
    let speedTest = SpeedTestToolModel()

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
        let total = count
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
    @Published var type: DNSRecordType = .a
    @Published var resolverChoice = "cloudflare"
    @Published var customResolver = "1.1.1.1"
    @Published private(set) var result: DNSLookupResult?
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

    func clear() {
        task?.cancel()
        task = nil
        result = nil
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
    @Published private(set) var isRunning = false
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
            let scan = await scanner.scan(
                host: target.host, ports: ports, timeout: timeout, concurrency: concurrency)
            self.results = scan
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
                    host: target.host, maxHops: hops, waitSeconds: 2)
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
            do {
                let result = try await service.run(
                    host: target.host, rounds: totalRounds, maxHops: hops, waitSeconds: 1
                ) { update in
                    Task { @MainActor [weak self] in
                        self?.report = update
                    }
                }
                if Task.isCancelled { return }
                self.report = result
            } catch is CancellationError {
                // Keep the last partial report.
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
        if let subnet = SubnetCalculator.parseCIDR(input) {
            result = subnet
            errorMessage = nil
        } else {
            result = nil
            errorMessage = "Enter a valid IPv4 CIDR, for example 192.168.1.0/24."
        }
    }
}

// MARK: - Path check

@MainActor
final class PathCheckToolModel: ObservableObject {
    @Published var target = "example.com:443"
    @Published private(set) var outcome: TCPProbeOutcome?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        guard let parsed = ToolTarget.parse(target, defaultPort: 443), let port = parsed.port else {
            errorMessage = "Use host:port, for example example.com:443."
            return
        }
        errorMessage = nil
        outcome = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            let result = await TCPProbe.connect(
                host: parsed.host, port: port, timeout: 4)
            self.outcome = result
            self.isRunning = false
            self.task = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        outcome = nil
        errorMessage = nil
        isRunning = false
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
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var isInstalled: Bool { Iperf3Runner.locate() != nil }

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

    var selectedSubnet: String { result?.subnet ?? "Not scanned" }

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
        errorMessage = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let measured = try await Task.detached(priority: .userInitiated) {
                    try await ThroughputTester.run()
                }.value
                self.report = measured
                self.record(measured)
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
