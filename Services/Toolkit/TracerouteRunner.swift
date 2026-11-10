import Foundation

enum TracerouteError: Error, Equatable, LocalizedError {
    case unavailable
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The system traceroute binary is unavailable."
        case .timedOut:
            return "Traceroute did not finish in time."
        case .failed(let message):
            return message.isEmpty ? "Traceroute failed." : message
        }
    }
}

protocol TracerouteRunning: Sendable {
    func trace(host: String, maxHops: Int, waitSeconds: Int) async throws -> TracerouteReport
}

/// `/usr/sbin/traceroute` is setuid root on macOS, so it can reach per-hop
/// addresses without the app asking for administrator rights. The binary is
/// still isolated behind this runner so a privileged helper can replace it.
struct SystemTracerouteRunner: TracerouteRunning {
    static func arguments(host: String, maxHops: Int, waitSeconds: Int) -> [String] {
        [
            "-n",
            "-m", String(max(1, min(maxHops, 64))),
            "-w", String(max(1, min(waitSeconds, 10))),
            "-q", "1",
            host,
        ]
    }

    func trace(host: String, maxHops: Int = 30, waitSeconds: Int = 2) async throws
        -> TracerouteReport
    {
        try await Task.detached(priority: .utility) {
            let executable = "/usr/sbin/traceroute"
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw TracerouteError.unavailable
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Self.arguments(
                host: host, maxHops: maxHops, waitSeconds: waitSeconds)
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()

            let deadline =
                Date().addingTimeInterval(Double(maxHops) * Double(waitSeconds) + 10)
            while process.isRunning && Date() < deadline {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    process.terminate()
                    throw error
                }
            }
            if process.isRunning {
                process.terminate()
                throw TracerouteError.timedOut
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw TracerouteError.failed(errorText)
            }
            return TracerouteParser.parse(text, host: host)
        }.value
    }
}
