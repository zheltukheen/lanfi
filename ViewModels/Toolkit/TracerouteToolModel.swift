import Foundation
import SwiftUI
import LanFiCore

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
        AnalysisTarget.shared.remember(host)
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
