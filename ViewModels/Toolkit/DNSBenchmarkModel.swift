import Foundation
import SwiftUI

/// Drives the resolver benchmark card on the DNS screen. Read-only: it measures
/// and ranks, and never touches the system resolver setting.
@MainActor
final class DNSBenchmarkModel: ObservableObject {
    @Published private(set) var report: DNSBenchmarkReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    func run() {
        guard !isRunning else { return }
        errorMessage = nil
        report = nil
        isRunning = true
        task = Task { [weak self] in
            let report = await DNSBenchmarkService().run(resolvers: DNSBenchmarkResolver.defaults)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            self.report = report
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
