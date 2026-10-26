import Foundation

/// Persists the last diagnostics runs so monitoring survives app restarts.
final class DiagnosticsHistoryStore {
    private let fileURL: URL
    private let limit: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil, limit: Int = 12) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("diagnostics-history.json")
        self.limit = max(1, limit)
        encoder.dateEncodingStrategy = .millisecondsSince1970
        decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    func load() -> [DiagnosticsReport] {
        guard let data = try? Data(contentsOf: fileURL),
            let reports = try? decoder.decode([DiagnosticsReport].self, from: data)
        else { return [] }
        return reports.sorted { $0.startedAt < $1.startedAt }.suffix(limit).map { $0 }
    }

    func save(_ reports: [DiagnosticsReport]) {
        let trimmed = reports.sorted { $0.startedAt < $1.startedAt }.suffix(limit)
        guard let data = try? encoder.encode(Array(trimmed)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
