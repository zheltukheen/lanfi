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

/// Probe protocol used by `/usr/sbin/traceroute`. macOS defaults to UDP, but
/// many home routers and VPNs drop the UDP replies, so the visual trace starts
/// with ICMP and falls back to UDP when every hop stays silent.
enum TracerouteProbe: String, Sendable, CaseIterable {
    case icmp
    case udp
}

protocol TracerouteRunning: Sendable {
    func trace(
        host: String, maxHops: Int, waitSeconds: Int, probes: Int, resolveNames: Bool
    ) async throws -> TracerouteReport
}

extension TracerouteRunning {
    func trace(host: String, maxHops: Int, waitSeconds: Int) async throws -> TracerouteReport {
        try await trace(
            host: host, maxHops: maxHops, waitSeconds: waitSeconds, probes: 1,
            resolveNames: false)
    }
}

/// Incremental trace used by Visual Traceroute: hops are yielded as
/// `traceroute` prints them, so the map can grow while the probe is running.
protocol TracerouteStreaming: Sendable {
    func stream(
        host: String, maxHops: Int, waitSeconds: Int, probes: Int, resolveNames: Bool,
        probe: TracerouteProbe
    ) -> AsyncThrowingStream<TracerouteHop, Error>
}

/// `/usr/sbin/traceroute` is setuid root on macOS, so it can reach per-hop
/// addresses without the app asking for administrator rights. The binary is
/// still isolated behind this runner so a privileged helper can replace it.
struct SystemTracerouteRunner: TracerouteRunning, TracerouteStreaming {
    static func arguments(
        host: String, maxHops: Int, waitSeconds: Int, probes: Int = 1,
        resolveNames: Bool = false, probe: TracerouteProbe = .icmp
    ) -> [String] {
        var arguments: [String] = []
        if !resolveNames { arguments.append("-n") }
        arguments += [
            "-P", probe.rawValue,
            "-m", String(max(1, min(maxHops, 64))),
            "-w", String(max(1, min(waitSeconds, 10))),
            "-q", String(max(1, min(probes, 3))),
            host,
        ]
        return arguments
    }

    func trace(
        host: String, maxHops: Int = 30, waitSeconds: Int = 2, probes: Int = 1,
        resolveNames: Bool = false
    ) async throws -> TracerouteReport {
        let first = try await runOnce(
            host: host, maxHops: maxHops, waitSeconds: waitSeconds, probes: probes,
            resolveNames: resolveNames, probe: .icmp)
        if first.hops.contains(where: { $0.address != nil }) { return first }

        // Every hop was filtered: give the default UDP probes a chance as well.
        if let fallback = try? await runOnce(
            host: host, maxHops: maxHops, waitSeconds: waitSeconds, probes: probes,
            resolveNames: resolveNames, probe: .udp),
            fallback.hops.contains(where: { $0.address != nil })
        {
            return fallback
        }
        return first
    }

    private func runOnce(
        host: String, maxHops: Int, waitSeconds: Int, probes: Int, resolveNames: Bool,
        probe: TracerouteProbe
    ) async throws -> TracerouteReport {
        let arguments = Self.arguments(
            host: host, maxHops: maxHops, waitSeconds: waitSeconds, probes: probes,
            resolveNames: resolveNames, probe: probe)
        return try await Task.detached(priority: .utility) {
            let executable = "/usr/sbin/traceroute"
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw TracerouteError.unavailable
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()

            let deadline =
                Date().addingTimeInterval(
                    Double(maxHops) * Double(waitSeconds) * Double(max(probes, 1)) + 10)
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

    // MARK: - Streaming

    func stream(
        host: String, maxHops: Int = 30, waitSeconds: Int = 2, probes: Int = 1,
        resolveNames: Bool = false, probe: TracerouteProbe = .icmp
    ) -> AsyncThrowingStream<TracerouteHop, Error> {
        let arguments = Self.arguments(
            host: host, maxHops: maxHops, waitSeconds: waitSeconds, probes: probes,
            resolveNames: resolveNames, probe: probe)

        return AsyncThrowingStream { continuation in
            let executable = "/usr/sbin/traceroute"
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                continuation.finish(throwing: TracerouteError.unavailable)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors

            let state = TracerouteStreamState()
            let deadline =
                Date().addingTimeInterval(
                    Double(maxHops) * Double(waitSeconds) * Double(max(probes, 1)) + 10)
            let watchdog = DispatchWorkItem {
                guard process.isRunning else { return }
                state.markTimedOut()
                process.terminate()
            }
            DispatchQueue.global(qos: .utility)
                .asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: watchdog)

            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in state.append(data) {
                    Self.yield(line, to: continuation, state: state)
                }
            }

            process.terminationHandler = { finished in
                watchdog.cancel()
                output.fileHandleForReading.readabilityHandler = nil
                let remainder = output.fileHandleForReading.readDataToEndOfFile()
                for line in state.append(remainder) {
                    Self.yield(line, to: continuation, state: state)
                }
                let errorText = String(
                    decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                if state.timedOut {
                    continuation.finish(throwing: TracerouteError.timedOut)
                } else if finished.terminationStatus != 0 && state.hopCount == 0 {
                    continuation.finish(throwing: TracerouteError.failed(errorText))
                } else {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                watchdog.cancel()
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                continuation.finish(throwing: error)
            }
        }
    }

    private static func yield(
        _ line: String, to continuation: AsyncThrowingStream<TracerouteHop, Error>.Continuation,
        state: TracerouteStreamState
    ) {
        guard let hop = TracerouteParser.parseLine(line), state.claim(ttl: hop.ttl) else { return }
        continuation.yield(hop)
    }
}

/// Thread-safe accumulation for a streaming traceroute.
private final class TracerouteStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var seen = Set<Int>()
    private var didTimeOut = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTimeOut
    }

    var hopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return seen.count
    }

    func markTimedOut() {
        lock.lock()
        didTimeOut = true
        lock.unlock()
    }

    /// Splits incoming bytes into complete lines, keeping the trailing partial
    /// line for the next chunk.
    func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer += String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        while let index = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(buffer[buffer.startIndex..<index])
            buffer = String(buffer[buffer.index(after: index)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func claim(ttl: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return seen.insert(ttl).inserted
    }
}
