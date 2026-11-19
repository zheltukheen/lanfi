import Foundation
import SwiftUI

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
