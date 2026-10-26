import AppKit
import Foundation

/// Local-only crash breadcrumbs. No network, no third-party SDK.
enum CrashLogger {
    private static let logDirectory: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/LanFi", isDirectory: true)
    }()

    static func install() {
        NSSetUncaughtExceptionHandler(lanFiUncaughtExceptionHandler)
    }

    fileprivate static func capture(_ exception: NSException) {
        let payload: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "name": exception.name.rawValue,
            "reason": exception.reason ?? "",
            "stack": exception.callStackSymbols,
        ]
        write(payload, prefix: "exception")
    }

    static func logDirectoryURL() -> URL {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        return logDirectory
    }

    static func recentLogs(limit: Int = 5) -> [URL] {
        let directory = logDirectoryURL()
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
        return
            files
            .filter { $0.pathExtension == "json" }
            .sorted {
                let left =
                    (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let right =
                    (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return left > right
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func write(_ payload: [String: Any], prefix: String) {
        let directory = logDirectoryURL()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(prefix)-\(stamp)-\(UUID().uuidString.prefix(6)).json")
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private func lanFiUncaughtExceptionHandler(_ exception: NSException) {
    CrashLogger.capture(exception)
}
