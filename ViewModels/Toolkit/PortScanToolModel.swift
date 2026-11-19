import Foundation
import SwiftUI

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
    @Published private(set) var totalPorts = 0
    @Published var detectServices = true
    @Published var includeUDP = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var scanToken = UUID()

    var openCount: Int { results.filter { $0.state == .open }.count }
    var closedCount: Int { results.filter { $0.state == .closed }.count }
    var filteredCount: Int { results.filter { $0.state == .filtered }.count }

    func applyPreset(_ preset: PortPreset) {
        portSpec = preset.ports.map(String.init).joined(separator: ",")
    }

    func run() {
        guard !isRunning else { return }
        AnalysisTarget.shared.remember(host)
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
        udpResults = []
        totalPorts = ports.count
        isRunning = true
        let token = UUID()
        scanToken = token
        let scanner = PortScanner(probe: TCPPortProbe())
        let timeout = timeout
        let concurrency = concurrency
        let detectServices = detectServices
        let includeUDP = includeUDP
        task = Task { [weak self] in
            guard let self else { return }

            // Stream every TCP result as it arrives. Insert in port order so
            // the table stays stable while it fills.
            for await result in scanner.stream(
                host: target.host, ports: ports, timeout: timeout, concurrency: concurrency)
            {
                guard self.scanToken == token else { return }
                Self.insert(result, into: &self.results)
            }
            guard self.scanToken == token, !Task.isCancelled else { return }

            if detectServices {
                let openPorts = self.results.filter { $0.state == .open }.map(\.port)
                await withTaskGroup(of: (UInt16, String?).self) { group in
                    for port in openPorts {
                        group.addTask {
                            let banner = await ServiceBannerProbe().probe(
                                host: target.host, port: port)
                            return (port, banner)
                        }
                    }
                    for await (port, banner) in group {
                        guard self.scanToken == token else {
                            group.cancelAll()
                            return
                        }
                        guard let banner,
                            let index = self.results.firstIndex(where: { $0.port == port })
                        else { continue }
                        let existing = self.results[index]
                        self.results[index] = PortScanResult(
                            port: existing.port,
                            service: existing.service,
                            state: existing.state,
                            responseMilliseconds: existing.responseMilliseconds,
                            detail: banner
                        )
                    }
                }
            }
            guard self.scanToken == token, !Task.isCancelled else { return }

            if includeUDP {
                let udpPorts: [UInt16] = [53, 67, 68, 69, 123, 137, 161, 500, 1900, 5353]
                let udpScanner = PortScanner(probe: UDPPortProbe())
                for await result in udpScanner.stream(
                    host: target.host, ports: udpPorts, timeout: timeout,
                    concurrency: min(concurrency, 10))
                {
                    guard self.scanToken == token else { return }
                    Self.insert(result, into: &self.udpResults)
                }
            }
            guard self.scanToken == token else { return }
            self.isRunning = false
            self.task = nil
        }
    }

    private static func insert(_ result: PortScanResult, into list: inout [PortScanResult]) {
        if let index = list.firstIndex(where: { $0.port > result.port }) {
            list.insert(result, at: index)
        } else {
            list.append(result)
        }
    }

    func stop() {
        scanToken = UUID()
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        results = []
        udpResults = []
        totalPorts = 0
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
