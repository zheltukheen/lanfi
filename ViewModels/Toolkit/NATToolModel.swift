import AppKit
import Foundation
import SwiftUI

@MainActor
final class NATToolModel: ObservableObject {
    @Published var server =
        STUNEndpoint.builtIn.first.map { "\($0.address):\($0.port)" }
        ?? "stun.l.google.com:19302"
    @Published private(set) var report: NATReport?
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    /// Runs the session against the typed server first, then the other built-in
    /// one, so the mapping can be compared without asking the user for two
    /// addresses.
    func run() {
        guard !isRunning else { return }
        guard let primary = STUNEndpoint.parse(server) else {
            errorMessage = STUNError.invalidServer.localizedDescription
            return
        }
        errorMessage = nil
        report = nil
        isRunning = true
        let servers = [primary] + STUNEndpoint.builtIn.filter { $0.address != primary.address }
        task = Task { [weak self] in
            let result = await STUNTester(servers: servers).run()
            guard let self else { return }
            if Task.isCancelled { return }
            self.report = result
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

    func copy() {
        guard let report else { return }
        var lines = [
            "LanFi NAT test · \(report.verdict.title)", "",
            "Local: \(report.localEndpoint.label)",
            "External: \(report.externalEndpoint?.label ?? "—")",
            "Mapping: \(report.mapping.label)",
            "Filtering: \(report.filtering.label)",
            "Port preserved: \(report.portPreserved ? "yes" : "no")",
            "",
        ]
        for probe in report.probes {
            lines.append("\(probe.server.label)\t\(probe.answerText)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
