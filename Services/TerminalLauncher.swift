import AppKit
import Foundation

/// P3.9 — opens a prepared `ssh` command in Terminal, or copies it for users
/// who keep their own terminal emulator. LanFi never reads, stores or types a
/// password, and it never creates a key.
enum TerminalLauncher {
    struct Result: Equatable {
        let succeeded: Bool
        let message: String
    }

    /// `osascript` rather than a temporary `.command` file: one process, no
    /// leftover scripts, and the command is passed as an AppleScript literal.
    ///
    /// The AppleScript request runs off the main actor: the first call may wait
    /// on the Automation permission sheet, and blocking the button handler there
    /// would freeze the window. The caller awaits the outcome and shows the
    /// message, including a refused or missing permission.
    static func open(command: String) async -> Result {
        await Task.detached(priority: .userInitiated) { run(command: command) }.value
    }

    /// Blocking implementation, only called from the detached task above.
    private static func run(command: String) -> Result {
        guard !command.isEmpty else {
            return Result(succeeded: false, message: String(localized: "Nothing to run."))
        }

        let script = """
            tell application "Terminal"
                activate
                do script "\(appleScriptEscaped(command))"
            end tell
            """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return Result(succeeded: false, message: error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(
                succeeded: false,
                message: message.isEmpty ? String(localized: "Terminal did not accept the command.") : message
            )
        }
        return Result(succeeded: true, message: String(localized: "Opened in Terminal."))
    }

    /// AppleScript string literals escape backslashes first, then quotes; the
    /// shell quoting in the command is already in place.
    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The "copy the command instead" path, for users with another terminal.
    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
