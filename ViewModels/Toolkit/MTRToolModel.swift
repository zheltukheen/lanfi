import Foundation
import SwiftUI
import LanFiCore

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
    /// Bumped on start and stop so a cancelled run cannot clear the state of
    /// the run that replaced it.
    private var runID = 0

    func run() {
        guard !isRunning else { return }
        AnalysisTarget.shared.remember(host)
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
        runID += 1
        let current = runID
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await service.run(
                    host: target.host, rounds: totalRounds, maxHops: hops, waitSeconds: 1
                ) { update in
                    Task { @MainActor [weak self] in
                        guard let self, self.runID == current else { return }
                        self.report = update
                    }
                }
                guard !Task.isCancelled, self.runID == current else { return }
                self.report = result
            } catch is CancellationError {
                return
            } catch {
                guard self.runID == current else { return }
                self.errorMessage = error.localizedDescription
            }
            guard self.runID == current else { return }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        runID += 1
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
