import Foundation

/// Feeds a growing pcap file into Wireshark while tcpdump is still writing it.
///
/// Airtool pipes tcpdump straight into Wireshark. LanFi cannot do that over
/// `osascript`: the privileged shell's stdout is AppleScript text, not a byte
/// stream. Instead Wireshark reads a pipe the app owns and the app tails the
/// capture file it is already validating, so the privileged side stays exactly
/// as before and Wireshark never runs as root.
final class WiresharkLiveStream: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "app.lanfi.capture.wireshark")
    private var process: Process?
    private var input: Pipe?
    private var timer: DispatchSourceTimer?
    private var offset: UInt64 = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Wireshark from /Applications, or a command-line build from Homebrew.
    static var executableURL: URL? {
        let candidates = [
            "/Applications/Wireshark.app/Contents/MacOS/Wireshark",
            "/opt/homebrew/bin/wireshark",
            "/usr/local/bin/wireshark",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static var isAvailable: Bool { executableURL != nil }

    func start() throws {
        guard let executable = Self.executableURL else {
            throw LiveCaptureError.captureFailed(
                "Wireshark is not installed, so the capture cannot be streamed.")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-k", "-i", "-"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.input = input

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.25, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.pump()
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops tailing and closes Wireshark. Safe to call twice.
    func stop() {
        timer?.cancel()
        timer = nil
        input?.fileHandleForWriting.closeFile()
        input = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    /// Called on `queue` only.
    private func pump() {
        guard let process, process.isRunning, let input else { return }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber
        let available = UInt64(size?.intValue ?? 0)
        guard available > offset else { return }
        guard let reader = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? reader.close() }
        do {
            try reader.seek(toOffset: offset)
            while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty {
                try input.fileHandleForWriting.write(contentsOf: chunk)
                offset += UInt64(chunk.count)
            }
        } catch {
            // Wireshark closed the pipe or the file was rotated away: stop
            // tailing instead of retrying a broken stream forever.
            timer?.cancel()
            timer = nil
        }
    }
}
