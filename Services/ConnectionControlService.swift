import AppKit
import Darwin
import Foundation

/// Process-level actions behind the Connections screen.
///
/// LanFi does not install a kernel extension or a privileged helper: killing an
/// endpoint means terminating the process that owns it with SIGTERM, which only
/// works for processes this user owns. The UI states that instead of pretending
/// a socket can be closed from outside.
enum ConnectionControlService {
    struct Result: Equatable {
        let succeeded: Bool
        let message: String
    }

    /// Display name of the running app for a PID, used to group helpers under
    /// one application instead of a dozen executable names.
    static func applicationName(for pid: Int) -> String? {
        NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName
    }

    static func terminate(pid: Int) -> Result {
        guard pid > 1 else {
            return Result(
                succeeded: false,
                message: String(localized: "PID \(pid) is a system process and cannot be killed."))
        }
        guard pid != Int(getpid()) else {
            return Result(
                succeeded: false,
                message: String(localized: "LanFi will not terminate itself."))
        }
        if kill(pid_t(pid), SIGTERM) == 0 {
            return Result(
                succeeded: true,
                message: String(localized: "Sent SIGTERM to PID \(pid)."))
        }
        let reason = String(cString: strerror(errno))
        return Result(
            succeeded: false,
            message: String(localized: "Could not terminate PID \(pid): \(reason)"))
    }
}
