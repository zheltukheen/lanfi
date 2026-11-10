import Foundation
import SwiftUI

@MainActor
final class ToolkitViewModel: ObservableObject {
    @Published var selection: ToolboxTool = .internetCheck

    let ping = PingToolModel()
    let dns = DNSToolModel()
    let portScan = PortScanToolModel()
    let traceroute = TracerouteToolModel()
    let ssl = SSLToolModel()
    let subnet = SubnetToolModel()
    let pathCheck = PathCheckToolModel()
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

// MARK: - Speed test

@MainActor
final class SpeedTestToolModel: ObservableObject {
    @Published private(set) var report: ThroughputReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

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
