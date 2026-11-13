import Foundation

struct ToolInstallResult: Sendable {
    let succeeded: Bool
    let message: String
}

/// Installs optional command-line helpers from Homebrew without making the
/// user leave the app. The installer is deliberately small: it only runs
/// `brew install <formula>` and reports the output. It never uses a shell.
enum ToolInstaller {
    static let brewCandidates = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
    ]

    static func locateBrew() -> String? {
        brewCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func command(for package: String) -> String {
        "brew install \(package)"
    }

    static func install(package: String, timeout: TimeInterval = 15 * 60) async -> ToolInstallResult {
        guard let brew = locateBrew() else {
            return ToolInstallResult(
                succeeded: false,
                message: String(
                    format: String(
                        localized:
                            "Homebrew was not found. Install it from https://brew.sh, then run `%@`."
                    ), command(for: package))
            )
        }

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["install", package]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
            } catch {
                return ToolInstallResult(
                    succeeded: false,
                    message: String(
                        format: String(localized: "Could not start Homebrew: %@"),
                        error.localizedDescription)
                )
            }

            // Drain both pipes while the process runs; `brew install` can print
            // more than the 64 KB pipe buffer.
            let stdoutTask = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
            let stderrTask = Task.detached { errors.fileHandleForReading.readDataToEndOfFile() }

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            if process.isRunning {
                process.terminate()
                return ToolInstallResult(
                    succeeded: false,
                    message: String(
                        format: String(localized: "Homebrew did not finish within %lld minutes."),
                        Int(timeout / 60))
                )
            }

            let stdout = String(decoding: await stdoutTask.value, as: UTF8.self)
            let stderr = String(decoding: await stderrTask.value, as: UTF8.self)
            let text = [stdout, stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            if process.terminationStatus == 0 {
                return ToolInstallResult(
                    succeeded: true,
                    message: text.isEmpty
                        ? String(format: String(localized: "%@ installed."), package) : text
                )
            }
            return ToolInstallResult(
                succeeded: false,
                message: text.isEmpty
                    ? String(
                        format: String(localized: "Homebrew exited with %lld."),
                        process.terminationStatus)
                    : text
            )
        }.value
    }
}
