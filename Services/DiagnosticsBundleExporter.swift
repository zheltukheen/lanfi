import AppKit
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsBundleExporter {
    static func makeBundle(
        report: DiagnosticsReport?,
        history: [DiagnosticsReport],
        interfaces: InterfacesReport?,
        directory: URL
    ) throws -> URL {
        let fileManager = FileManager.default
        let root = directory.appendingPathComponent("LanFi-Diagnostics-\(timestamp())", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        if let report, let data = try? encoder.encode(report) {
            try data.write(to: root.appendingPathComponent("diagnostics-report.json"), options: .atomic)
        }
        if let historyData = try? encoder.encode(history) {
            try historyData.write(to: root.appendingPathComponent("diagnostics-history.json"), options: .atomic)
        }
        if let interfaces, let data = try? encoder.encode(interfaces) {
            try data.write(to: root.appendingPathComponent("interfaces.json"), options: .atomic)
        }

        let summary = """
            LanFi diagnostics bundle
            Generated: \(Date().formatted(date: .abbreviated, time: .standard))
            Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            Build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-")
            Bundle: \(Bundle.main.bundleIdentifier ?? "-")
            macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Host: \(ProcessInfo.processInfo.hostName)

            This bundle is generated locally. It contains no location samples,
            packet payloads, credentials or remote-sensor keys.
            """
        try summary.write(to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let system = run("/usr/bin/sw_vers")
        try system.write(to: root.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)

        let crashDirectory = root.appendingPathComponent("crashes", isDirectory: true)
        try fileManager.createDirectory(at: crashDirectory, withIntermediateDirectories: true)
        for log in CrashLogger.recentLogs() {
            try? fileManager.copyItem(at: log, to: crashDirectory.appendingPathComponent(log.lastPathComponent))
        }

        let zip = directory.appendingPathComponent("\(root.lastPathComponent).zip")
        try? fileManager.removeItem(at: zip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, zip.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "LanFi.Diagnostics", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create the diagnostics zip."
                ])
        }
        return zip
    }

    @MainActor
    static func exportWithPanel(
        report: DiagnosticsReport?,
        history: [DiagnosticsReport],
        interfaces: InterfacesReport?
    ) {
        let panel = NSSavePanel()
        panel.title = "Export LanFi diagnostics"
        panel.nameFieldStringValue = "LanFi-Diagnostics-\(timestamp()).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let temporary = FileManager.default.temporaryDirectory
            let bundle = try makeBundle(
                report: report, history: history, interfaces: interfaces,
                directory: temporary
            )
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: bundle, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Diagnostics export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func run(_ executable: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        } catch {
            return ""
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private extension UTType {
    static var zip: UTType { UTType(filenameExtension: "zip") ?? .data }
}
