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
    private let historyStore = DiagnosticsHistoryStore()
    private var monitorTask: Task<Void, Never>?

    init() {
        history = historyStore.load()
        report = history.last
    }

    var overall: DiagnosticStatus {
        report?.overall ?? .pending
    }

    var lastRunText: String {
        guard let report else { return "Not run yet" }
        return "\(report.summary) · \(Int(report.duration * 1000)) ms"
    }

    /// Public round-trip latency from the last run, for the menu-bar meter.
    var publicLatencyMilliseconds: Int? {
        guard
            let check = report?.checks.first(where: {
                $0.id == "latency" || $0.title == "Public latency"
            })
        else { return nil }
        let value = check.value.replacingOccurrences(of: " ms", with: "")
        return Double(value).map { Int($0.rounded()) }
    }

    /// Round-trip checks shown as a compact latency strip in the popover.
    var latencyChecks: [DiagnosticCheck] {
        guard let report else { return [] }
        return report.checks.filter {
            $0.category == .performance || ($0.category == .dns && $0.value.contains("ms"))
        }
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let result = await engine.run()
        report = result
        history.append(result)
        if history.count > 12 { history.removeFirst(history.count - 12) }
        historyStore.save(history)
        errorMessage = nil
    }

    func toggleMonitoring() {
        autoMonitor.toggle()
    }

    func selectHistory(_ item: DiagnosticsReport) {
        report = item
    }

    func clearHistory() {
        history.removeAll()
        historyStore.clear()
        report = nil
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
