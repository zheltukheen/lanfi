import CoreWLAN
import Darwin
import Foundation

struct LiveCaptureOptions: Equatable {
    let interfaceName: String
    let duration: Int
    let outputURL: URL
    let monitorMode: Bool
    var filter: String = ""
    var startDelay: Int = 0
    var channel: Int? = nil
    /// Multi-channel listening: a single channel pins, a longer list is tuned by
    /// the app while tcpdump runs.
    var channelPlan: CaptureChannelPlan? = nil
    /// Size cap and per-frame slicing.
    var limits: CaptureLimits = .none
    /// Tail the capture file into Wireshark while it is still being written.
    var streamToWireshark: Bool = false

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
        case .invalidDuration: return "Capture duration must be between 5 and 600 seconds."
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
    static let minimumDuration = 5
    static let maximumDuration = 600

    private static let captureLock = NSLock()

    static func clampedDuration(_ duration: Int) -> Int {
        min(max(duration, minimumDuration), maximumDuration)
    }

    /// The file the UI writes to ask a running capture to stop early. It lives
    /// next to the capture so the privileged shell can test it without any
    /// extra permission.
    static func stopURL(for outputURL: URL) -> URL {
        URL(fileURLWithPath: outputURL.path + ".stop")
    }

    static func requestStop(for outputURL: URL) {
        try? Data().write(to: stopURL(for: outputURL))
    }

    static func shellCommand(for options: LiveCaptureOptions) -> String {
        let duration = clampedDuration(options.duration)
        let startDelay = min(max(options.startDelay, 0), 120)
        let output = shellQuote(options.outputURL.path)
        let outputPrefix = shellQuote(options.outputURL.path) + "*"
        let errorPath = shellQuote(options.outputURL.path + ".tcpdump.log")
        let pidPath = shellQuote(options.outputURL.path + ".pid")
        let stopPath = shellQuote(stopURL(for: options.outputURL).path)
        var args = [
            "/usr/sbin/tcpdump",
            "-i", shellQuote(options.interfaceName),
            "-s", "0",
            "-U",
            "-n",
        ]
        if options.monitorMode {
            args.append(contentsOf: ["-I", "-y", "IEEE802_11_RADIO"])
        }
        // Rotation needs a single writer; a live stream tails the named file,
        // so the size cap is applied only when Wireshark is not watching.
        if !options.streamToWireshark {
            args.append(contentsOf: options.limits.tcpdumpArguments)
        }
        args.append(contentsOf: ["-w", output])
        if !options.filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(shellQuote(options.filter))
        }
        args.append(contentsOf: ["2>", errorPath])
        let command = args.joined(separator: " ")
        return [
            "sleep \(startDelay)",
            "\(command) & PID=$!",
            "echo $PID > \(pidPath); chmod 644 \(pidPath) 2>/dev/null || true",
            // A loop instead of one long sleep so Stop (and the watchdog) end
            // the capture within a second.
            "i=0; while [ $i -lt \(duration) ] && [ ! -f \(stopPath) ]; do sleep 1; i=$((i+1)); done",
            "kill -TERM $PID 2>/dev/null || true",
            "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 $PID 2>/dev/null || break; sleep 0.2; done",
            "kill -KILL $PID 2>/dev/null || true",
            "wait $PID 2>/dev/null || true",
            "chown \(getuid()):\(getgid()) \(outputPrefix) 2>/dev/null || true",
            "chmod 644 \(outputPrefix) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    static func validate(_ options: LiveCaptureOptions) throws {
        let name = options.interfaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil else {
            throw LiveCaptureError.invalidInterface
        }
        guard (minimumDuration...maximumDuration).contains(options.duration) else {
            throw LiveCaptureError.invalidDuration
        }
    }

    static func capture(_ options: LiveCaptureOptions) async throws -> URL {
        try validate(options)
        if options.monitorMode {
            let pinned: CaptureChannelRef? =
                options.channelPlan?.channels.count == 1
                ? options.channelPlan?.channels.first
                : options.channel.map { CaptureChannelRef(band: nil, channel: $0) }
            if let pinned { tune(interfaceName: options.interfaceName, to: pinned) }
        }
        guard captureLock.try() else { throw LiveCaptureError.captureInProgress }
        defer { captureLock.unlock() }

        let errorURL = URL(fileURLWithPath: options.outputURL.path + ".tcpdump.log")
        try? FileManager.default.removeItem(at: errorURL)
        try? FileManager.default.removeItem(at: stopURL(for: options.outputURL))
        for part in CaptureFiles.partURLs(base: options.outputURL) where part != options.outputURL {
            try? FileManager.default.removeItem(at: part)
        }

        // The command must describe the mode that actually runs: without
        // Wireshark there is no stream, and the size cap stays available.
        var effective = options
        effective.streamToWireshark = options.streamToWireshark && WiresharkLiveStream.isAvailable
        let streaming = effective.streamToWireshark
        let stream = streaming ? WiresharkLiveStream(fileURL: options.outputURL) : nil
        if let stream {
            do {
                try stream.start()
            } catch {
                stream.stop()
                throw error
            }
        }
        defer { stream?.stop() }

        let duration = clampedDuration(options.duration)
        let startDelay = min(max(options.startDelay, 0), 120)
        let command = shellCommand(for: effective)
        let script = "do shell script \\(appleScriptQuote(command)) with administrator privileges"

        // The supervisor owns the osascript lifetime: the capture counts as
        // started once tcpdump has written its pcap header (which happens after
        // authorization and after BPF opened the interface), and the whole run
        // is killed past the deadline. A prompt left open or a stuck tcpdump
        // therefore ends with an error instead of a frozen window.
        let errorPipe = Pipe()
        let supervisor = SupervisedProcess(
            SupervisedProcessConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script],
                errorPipe: errorPipe,
                readinessTimeout: readinessTimeout,
                runLimit: TimeInterval(startDelay + duration + 25),
                isReady: { captureHasStarted(at: options.outputURL) }))

        do {
            try await supervisor.start()
        } catch {
            await supervisor.stop()
            throw captureError(from: errorText(errorPipe))
        }

        if options.monitorMode, let plan = options.channelPlan, plan.isHopping {
            await hop(
                plan: plan, interfaceName: options.interfaceName,
                until: Date().addingTimeInterval(TimeInterval(duration)),
                stopURL: stopURL(for: options.outputURL), supervisor: supervisor)
        }

        let status = await supervisor.waitUntilExit()
        guard status == 0 else {
            throw captureError(from: errorText(errorPipe))
        }

        let parts = CaptureFiles.partURLs(base: options.outputURL)
        let size = CaptureFiles.totalSize(of: parts)
        guard size > CaptureFiles.globalHeaderLength else {
            for part in parts { try? FileManager.default.removeItem(at: part) }
            throw LiveCaptureError.captureFailed(
                "No packets were written. For Wi-Fi monitor capture, disable Monitor mode or use a supported adapter."
            )
        }

        do {
            try CaptureFiles.mergeParts(base: options.outputURL)
        } catch {
            throw LiveCaptureError.captureFailed(error.localizedDescription)
        }
        if options.limits.slicesDataFrames, let limit = options.limits.sliceDataFrameBytes {
            _ = try? PcapDataFrameSlicer.sliceInPlace(
                url: options.outputURL, maxDataFrameBytes: limit)
        }
        do {
            _ = try PcapAnalyzer.parse(data: PcapAnalyzer.mappedData(at: options.outputURL))
        } catch let error as PcapAnalyzerError {
            throw LiveCaptureError.captureFailed(error.localizedDescription)
        } catch {
            throw LiveCaptureError.captureFailed(error.localizedDescription)
        }
        return options.outputURL
    }

    /// Tunes the monitor interface while tcpdump writes. CoreWLAN allows a
    /// channel change without elevation, which is how the passive scan engine
    /// already sweeps; the capture keeps every frame the radio delivers on the
    /// channel it is tuned to.
    private static func hop(
        plan: CaptureChannelPlan,
        interfaceName: String,
        until end: Date,
        stopURL: URL,
        supervisor: SupervisedProcess
    ) async {
        let dwell = UInt64(plan.dwellMilliseconds) * 1_000_000
        var index = 0
        while Date() < end {
            if FileManager.default.fileExists(atPath: stopURL.path) { break }
            if await supervisor.isRunning == false { break }
            tune(
                interfaceName: interfaceName,
                to: plan.channels[index % plan.channels.count])
            index += 1
            try? await Task.sleep(nanoseconds: dwell)
        }
    }

    /// Tunes the monitor interface to one planned channel. CoreWLAN allows this
    /// without elevation, which is how the passive scan engine already sweeps.
    private static func tune(interfaceName: String, to reference: CaptureChannelRef) {
        guard let interface = CWWiFiClient.shared().interface(withName: interfaceName),
            let supported = interface.supportedWLANChannels()
        else { return }
        let exact = supported.first { channel in
            channel.channelNumber == reference.channel
                && (reference.band == nil || band(channel.channelBand) == reference.band)
        }
        guard let channel = exact ?? supported.first(where: { $0.channelNumber == reference.channel })
        else { return }
        try? interface.setWLANChannel(channel)
    }

    private static func band(_ band: CWChannelBand?) -> WiFiBand? {
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return nil
        }
    }

    static func isCaptureLocked() -> Bool {
        if captureLock.try() {
            captureLock.unlock()
            return false
        }
        return true
    }

    /// Time the user has to approve the prompt and for tcpdump to write its
    /// first bytes before the helper is treated as hung.
    static let readinessTimeout: TimeInterval = 120

    /// True once tcpdump has written the pcap global header. That only happens
    /// after authorization succeeded and BPF opened the interface, so it is a
    /// real readiness signal rather than "the process exists".
    static func captureHasStarted(at url: URL) -> Bool {
        let size =
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size]
            as? NSNumber
        return (size?.intValue ?? 0) >= CaptureFiles.globalHeaderLength
    }

    static func captureError(from text: String) -> LiveCaptureError {
        if text.localizedCaseInsensitiveContains("cancel") {
            return .authorizationCancelled
        }
        if text.isEmpty {
            return .captureFailed(
                "The capture did not start. Check the interface, then try again.")
        }
        return .captureFailed(text)
    }

    private static func errorText(_ pipe: Pipe) -> String {
        String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
