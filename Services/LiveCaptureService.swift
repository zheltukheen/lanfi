import Darwin
import Foundation

struct LiveCaptureOptions: Equatable {
    let interfaceName: String
    let duration: Int
    let outputURL: URL
    let monitorMode: Bool

    var isWiFi: Bool { interfaceName == "en0" || monitorMode }
}

enum LiveCaptureError: LocalizedError {
    case invalidInterface
    case invalidDuration
    case authorizationCancelled
    case captureFailed(String)
    case emptyCapture
    case captureInProgress

    var errorDescription: String? {
        switch self {
        case .invalidInterface: return "Choose a valid network interface."
        case .invalidDuration: return "Capture duration must be between 5 and 120 seconds."
        case .authorizationCancelled: return "Administrator authorization was cancelled."
        case .captureFailed(let message): return message
        case .emptyCapture: return "The capture finished without writing any packets."
        case .captureInProgress: return "Another capture is already running."
        }
    }
}

/// Live capture uses the system tcpdump/BPF stack. macOS has no unprivileged
/// BPF access, so the user is asked for one-off administrator authorization.
/// No helper is installed and no credentials are stored.
enum LiveCaptureService {
    private static let captureLock = NSLock()

    static func shellCommand(for options: LiveCaptureOptions) -> String {
        let duration = min(max(options.duration, 5), 120)
        let output = shellQuote(options.outputURL.path)
        let errorPath = shellQuote(options.outputURL.path + ".tcpdump.log")
        let pidPath = shellQuote(options.outputURL.path + ".pid")
        var args = [
            "/usr/sbin/tcpdump",
            "-i", shellQuote(options.interfaceName),
            "-s", "0",
            "-U",
            "-n",
            "-w", output,
        ]
        if options.monitorMode {
            args.append(contentsOf: ["-I", "-y", "IEEE802_11_RADIO"])
        }
        args.append(contentsOf: ["2>", errorPath])
        let command = args.joined(separator: " ")
        return [
            "\(command) & PID=$!",
            "echo $PID > \(pidPath); chmod 644 \(pidPath) 2>/dev/null || true",
            "sleep \(duration)",
            "kill -TERM $PID 2>/dev/null || true",
            "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 $PID 2>/dev/null || break; sleep 0.2; done",
            "kill -KILL $PID 2>/dev/null || true",
            "wait $PID 2>/dev/null || true",
            "chown \(getuid()):\(getgid()) \(output) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    static func validate(_ options: LiveCaptureOptions) throws {
        let name = options.interfaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil else {
            throw LiveCaptureError.invalidInterface
        }
        guard (5...120).contains(options.duration) else {
            throw LiveCaptureError.invalidDuration
        }
    }

    static func capture(_ options: LiveCaptureOptions) async throws -> URL {
        try validate(options)
        guard captureLock.try() else { throw LiveCaptureError.captureInProgress }
        defer { captureLock.unlock() }
        let errorURL = URL(fileURLWithPath: options.outputURL.path + ".tcpdump.log")
        try? FileManager.default.removeItem(at: errorURL)
        let command = shellCommand(for: options)
        let script = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        let errorText = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            if errorText.localizedCaseInsensitiveContains("cancel") {
                throw LiveCaptureError.authorizationCancelled
            }
            throw LiveCaptureError.captureFailed(errorText.isEmpty ? "tcpdump failed." : errorText)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: options.outputURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 24 else {
            let stderr = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw LiveCaptureError.captureFailed(stderr.isEmpty ? "The capture file is empty." : stderr)
        }
        return options.outputURL
    }

    static func isCaptureLocked() -> Bool {
        if captureLock.try() {
            captureLock.unlock()
            return false
        }
        return true
    }

    static func interfaceNames() -> [String] {
        var names: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(first) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            let name = String(cString: entry.pointee.ifa_name)
            if !names.contains(name) { names.append(name) }
            current = entry.pointee.ifa_next
        }
        return names.sorted()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\""
            + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
