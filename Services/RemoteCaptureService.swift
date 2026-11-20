import Foundation

struct RemoteCaptureRequest {
    var sensor: RemoteSensor
    var interfaceName: String = "en0"
    var duration: Int = 20
    var monitorMode: Bool = true
    var filter: String = ""
}

enum RemoteCaptureService {
    static func validate(_ request: RemoteCaptureRequest) throws {
        try RemoteSensorService.validate(request.sensor)
        let iface = request.interfaceName.trimmingCharacters(in: .whitespaces)
        guard !iface.isEmpty, iface.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil else {
            throw RemoteSensorError.invalidResponse("Invalid remote interface.")
        }
        guard (5...120).contains(request.duration) else {
            throw RemoteSensorError.invalidResponse("Duration must be between 5 and 120 seconds.")
        }
    }

    static func script(for request: RemoteCaptureRequest, remotePath: String) -> String {
        let logPath = remotePath + ".log"
        var args = [
            "/usr/sbin/tcpdump", "-i", shellQuote(request.interfaceName), "-s", "0", "-U", "-n", "-w",
            shellQuote(remotePath),
        ]
        if request.monitorMode {
            args.append(contentsOf: ["-I", "-y", "IEEE802_11_RADIO"])
        }
        if !request.filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(shellQuote(request.filter))
        }
        let capture = "sudo -n " + args.joined(separator: " ") + " 2> \(shellQuote(logPath))"
        return [
            "set -e",
            "\(capture) & PID=$!",
            "sleep \(request.duration)",
            "sudo -n kill -TERM $PID 2>/dev/null || true",
            "for i in 1 2 3 4 5 6 7 8 9 10; do sudo -n kill -0 $PID 2>/dev/null || break; sleep 0.2; done",
            "sudo -n kill -KILL $PID 2>/dev/null || true",
            "wait $PID 2>/dev/null || true",
            "sudo -n chmod 644 \(shellQuote(remotePath)) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    static func capture(_ request: RemoteCaptureRequest, localURL: URL) async throws {
        try validate(request)
        let remotePath = "/tmp/lanfi-\(UUID().uuidString).pcap"
        var sshArguments = try RemoteSensorService.baseArguments(for: request.sensor)
        sshArguments.append("bash -lc \(shellQuote(script(for: request, remotePath: remotePath)))")
        // The remote script sleeps for `duration` and stops its own tcpdump, so
        // the allowance is that sleep plus a generous handshake margin. Without
        // the limit a hung ssh would look like a capture that never finishes.
        try await run(
            "/usr/bin/ssh", sshArguments, limit: TimeInterval(request.duration) + 60)

        var scpArguments = [
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-P", String(request.sensor.port),
        ]
        if let identity = request.sensor.identityFile?.trimmingCharacters(in: .whitespaces), !identity.isEmpty {
            scpArguments.append(contentsOf: ["-i", identity])
        }
        let remote = "\(request.sensor.username)@\(request.sensor.host):\(remotePath)"
        scpArguments.append(contentsOf: [remote, localURL.path])
        // A large pcap over a slow link is legitimate; a scp that never ends is not.
        try await run("/usr/bin/scp", scpArguments, limit: 15 * 60)

        var cleanup = try RemoteSensorService.baseArguments(for: request.sensor)
        cleanup.append("rm -f \(shellQuote(remotePath)) \(shellQuote(remotePath + ".log"))")
        try? await run("/usr/bin/ssh", cleanup, limit: 20)
    }

    /// Runs one remote command under supervision, so ssh cannot hang the
    /// capture and a stuck child is stopped with SIGTERM then SIGKILL.
    static func run(
        _ executable: String, _ arguments: [String], limit: TimeInterval
    ) async throws {
        let result: SupervisedCommandResult
        do {
            result = try await SupervisedCommand.run(executable, arguments, limit: limit)
        } catch {
            throw RemoteSensorError.sshFailed(error.localizedDescription)
        }
        guard result.status == 0 else {
            if result.timedOut && result.stderr.isEmpty {
                throw RemoteSensorError.sshFailed(
                    "The remote command did not finish in time and was stopped.")
            }
            throw RemoteSensorError.sshFailed(
                result.stderr.isEmpty ? "Remote capture failed." : result.stderr)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
