import Foundation
import SwiftUI
import LanFiCore

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
        AnalysisTarget.shared.remember(host)
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
