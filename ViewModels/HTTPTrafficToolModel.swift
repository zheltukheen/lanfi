import Foundation
import SwiftUI

@MainActor
final class HTTPTrafficToolModel: ObservableObject {
    @Published private(set) var traffic: HARTraffic?
    @Published private(set) var fileName = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var search = ""
    @Published var hostFilter = ""
    @Published var statusFilter: HARStatusFilter = .all
    /// Redacts credentials in exports, the inspector and copied cURL commands.
    /// The loaded capture itself is never modified.
    @Published var redactExports = true
    @Published var selectedEntryID: String?

    private var task: Task<Void, Never>?

    var insights: HARInsights? {
        traffic.map { HARTrafficAnalyzer.insights(for: $0) }
    }

    var hosts: [String] { traffic?.hosts ?? [] }

    var entries: [HAREntry] {
        guard let traffic else { return [] }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return traffic.entries.filter { entry in
            (hostFilter.isEmpty || entry.host == hostFilter)
                && statusFilter.matches(entry)
                && (term.isEmpty
                    || entry.request.url.lowercased().contains(term)
                    || entry.request.method.lowercased().contains(term)
                    || entry.response.mimeType.lowercased().contains(term))
        }
    }

    var selectedEntry: HAREntry? {
        guard let selectedEntryID else { return nil }
        return traffic?.entries.first { $0.id == selectedEntryID }
    }

    func load(_ url: URL) {
        task?.cancel()
        isLoading = true
        errorMessage = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try HARParser.parse(data: data)
                }.value
                if Task.isCancelled { return }
                self.traffic = parsed
                self.fileName = url.lastPathComponent
                self.hostFilter = ""
                self.selectedEntryID = parsed.entries.first?.id
                if parsed.entries.isEmpty {
                    self.errorMessage = String(localized: "This HAR archive contains no requests.")
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
            self.task = nil
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        traffic = nil
        fileName = ""
        selectedEntryID = nil
        hostFilter = ""
        search = ""
        errorMessage = nil
        isLoading = false
    }

    func markdownReport() -> String {
        guard let traffic else { return "" }
        return HARTrafficAnalyzer.markdownReport(for: traffic, redacted: redactExports)
    }

    func csv() -> String {
        HARExport.csv(for: entries, redacted: redactExports)
    }

    func curl(for entry: HAREntry) -> String {
        HARExport.curl(for: entry, redacted: redactExports)
    }

    func headers(for display: [HARHeader]) -> [HARHeader] {
        redactExports ? HARRedaction.headers(display) : display
    }
}
