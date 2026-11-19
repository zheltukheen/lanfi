import Foundation
import SwiftUI

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
        AnalysisTarget.shared.remember(query)
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
