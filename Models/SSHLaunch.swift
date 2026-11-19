import Foundation

/// P3.9 — the `ssh` command behind "Open in Terminal".
///
/// Pure and fully quoted: the fields come from a saved sensor or a scan result,
/// so every piece is wrapped for the shell and no password or key material is
/// ever read, generated or stored. Key-based login is the user's own setup.
struct SSHLaunchCommand: Equatable, Sendable {
    var host: String
    var user: String
    var port: Int
    var identityFile: String?

    init(host: String, user: String = "", port: Int = 22, identityFile: String? = nil) {
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
    }

    init(sensor: RemoteSensor) {
        self.init(
            host: sensor.host, user: sensor.username, port: sensor.port,
            identityFile: sensor.identityFile)
    }

    /// A LAN device only offers SSH when the scan actually found port 22 open;
    /// the username is unknown, so `ssh` asks for it.
    init?(device: LANDevice) {
        guard device.openPorts.contains(22) else { return nil }
        self.init(host: device.ip)
    }

    /// The executable line, ready for Terminal.
    var command: String {
        var parts = ["ssh"]
        if port > 0 && port != 22 {
            parts.append("-p")
            parts.append(String(port))
        }
        if let identity = identityFile?.trimmingCharacters(in: .whitespacesAndNewlines),
            !identity.isEmpty
        {
            parts.append("-i")
            parts.append(Self.quote(identity))
        }
        parts.append(Self.quote(user.isEmpty ? host : "\(user)@\(host)"))
        return parts.joined(separator: " ")
    }

    /// Worth offering the action at all: a host is required and it must not
    /// contain whitespace, which would make the destination unparseable.
    var isUsable: Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains(where: { $0.isWhitespace })
    }

    /// Human-readable form for headers and copy actions (`ssh user@host:port`).
    var summary: String {
        "ssh \(user.isEmpty ? "" : "\(user)@")\(host):\(port)"
    }

    /// Single-quote shell escaping: `O'Brien` → `'O'\''Brien'`.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
