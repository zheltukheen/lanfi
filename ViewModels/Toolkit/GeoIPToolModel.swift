import Foundation
import SwiftUI

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
