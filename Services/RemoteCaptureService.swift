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
        try run("/usr/bin/ssh", sshArguments)

        var scpArguments = [
            "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new",
            "-P", String(request.sensor.port),
        ]
        if let identity = request.sensor.identityFile?.trimmingCharacters(in: .whitespaces), !identity.isEmpty {
            scpArguments.append(contentsOf: ["-i", identity])
        }
        let remote = "\(request.sensor.username)@\(request.sensor.host):\(remotePath)"
        scpArguments.append(contentsOf: [remote, localURL.path])
        try run("/usr/bin/scp", scpArguments)

        var cleanup = try RemoteSensorService.baseArguments(for: request.sensor)
        cleanup.append("rm -f \(shellQuote(remotePath)) \(shellQuote(remotePath + ".log"))")
        try? run("/usr/bin/ssh", cleanup)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemoteSensorError.sshFailed(text.isEmpty ? "Remote capture failed." : text)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
