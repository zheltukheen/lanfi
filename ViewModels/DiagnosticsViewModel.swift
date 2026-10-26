import Foundation
import SwiftUI

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published private(set) var report: DiagnosticsReport?
    @Published private(set) var history: [DiagnosticsReport] = []
    @Published private(set) var isRunning = false
    @Published var autoMonitor = false {
        didSet {
            if autoMonitor {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }
    @Published var errorMessage: String?

    private let engine = NetworkDiagnosticsEngine()
    private var monitorTask: Task<Void, Never>?

    var overall: DiagnosticStatus {
        report?.overall ?? .pending
    }

    var lastRunText: String {
        guard let report else { return "Not run yet" }
        return "\(report.summary) · \(Int(report.duration * 1000)) ms"
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let result = await engine.run()
        report = result
        history.append(result)
        if history.count > 12 { history.removeFirst(history.count - 12) }
        errorMessage = nil
    }

    func toggleMonitoring() {
        autoMonitor.toggle()
    }

    func copyReport() {
        guard let report else { return }
        var lines = [
            "LanFi diagnostics \(report.startedAt.formatted(date: .abbreviated, time: .standard))",
            report.summary,
            "Overall: \(report.overall.label)",
            "",
        ]
        for check in report.checks {
            lines.append("[\(check.status.label)] \(check.title): \(check.value) — \(check.detail)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.autoMonitor {
                await self.run()
                if Task.isCancelled || !self.autoMonitor { break }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }
}
