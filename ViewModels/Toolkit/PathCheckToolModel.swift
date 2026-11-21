import Foundation
import SwiftUI
import LanFiCore

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
        AnalysisTarget.shared.remember(host)
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
