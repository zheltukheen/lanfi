import Foundation
import Network

protocol PortProbing: Sendable {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortScanResult
}

struct TCPPortProbe: PortProbing {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortScanResult {
        switch await TCPProbe.connect(host: host, port: port, timeout: timeout) {
        case .open(let milliseconds):
            return PortScanResult(
                port: port,
                service: PortServices.name(for: port),
                state: .open,
                responseMilliseconds: milliseconds
            )
        case .closed(let milliseconds, let detail):
            return PortScanResult(
                port: port,
                service: PortServices.name(for: port),
                state: .closed,
                responseMilliseconds: milliseconds,
                detail: detail
            )
        case .filtered(let detail):
            return PortScanResult(
                port: port,
                service: PortServices.name(for: port),
                state: .filtered,
                detail: detail
            )
        }
    }
}

struct PortScanner: Sendable {
    let probe: PortProbing

    func scan(
        host: String,
        ports: [UInt16],
        timeout: TimeInterval = 1.5,
        concurrency: Int = 24
    ) async -> [PortScanResult] {
        var results: [PortScanResult] = []
        for await result in stream(
            host: host, ports: ports, timeout: timeout, concurrency: concurrency)
        {
            results.append(result)
        }
        return results.sorted { $0.port < $1.port }
    }

    /// Yields each port as soon as its probe finishes and keeps a sliding
    /// window of probes in flight. A slow or silently dropped port therefore
    /// never blocks the rest of the list, and the UI fills progressively.
    func stream(
        host: String,
        ports: [UInt16],
        timeout: TimeInterval = 1.5,
        concurrency: Int = 24
    ) -> AsyncStream<PortScanResult> {
        let unique = Array(Set(ports)).sorted()
        let width = max(1, min(concurrency, 64))
        let probe = self.probe
        return AsyncStream { continuation in
            let task = Task {
                guard !unique.isEmpty else {
                    continuation.finish()
                    return
                }
                await withTaskGroup(of: PortScanResult.self) { group in
                    var nextIndex = 0
                    let initial = min(width, unique.count)
                    for _ in 0..<initial {
                        let port = unique[nextIndex]
                        nextIndex += 1
                        group.addTask {
                            await probe.probe(host: host, port: port, timeout: timeout)
                        }
                    }
                    while let result = await group.next() {
                        continuation.yield(result)
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        if nextIndex < unique.count {
                            let port = unique[nextIndex]
                            nextIndex += 1
                            group.addTask {
                                await probe.probe(host: host, port: port, timeout: timeout)
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct UDPPortProbe: PortProbing {
    func probe(host: String, port: UInt16, timeout: TimeInterval) async -> PortScanResult {
        let outcome = await UDPProbe.probe(host: host, port: port, timeout: timeout)
        return PortScanResult(
            port: port,
            service: PortServices.name(for: port) ?? "UDP",
            state: outcome.state,
            responseMilliseconds: outcome.milliseconds,
            detail: outcome.detail
        )
    }
}

private enum UDPProbe {
    struct Outcome {
        let state: PortState
        let milliseconds: Double?
        let detail: String
    }

    static func probe(host: String, port: UInt16, timeout: TimeInterval) async -> Outcome {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any,
                using: .udp
            )
            let box = Box(continuation: continuation)
            let started = Date()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(
                        content: Data([0]),
                        completion: .contentProcessed { error in
                            if error != nil {
                                box.finish(
                                    Outcome(
                                        state: .filtered, milliseconds: nil,
                                        detail: "UDP send failed"))
                                connection.cancel()
                            }
                        })
                    connection.receive(
                        minimumIncompleteLength: 1, maximumLength: 2048
                    ) { data, _, _, _ in
                        if data != nil {
                            box.finish(
                                Outcome(
                                    state: .open,
                                    milliseconds: Date().timeIntervalSince(started) * 1000,
                                    detail: "UDP response"))
                        } else {
                            box.finish(
                                Outcome(
                                    state: .filtered, milliseconds: nil,
                                    detail: "No UDP response (open|filtered)"))
                        }
                        connection.cancel()
                    }
                case .waiting(let error), .failed(let error):
                    let refused: Bool
                    if case .posix(let code) = error {
                        refused = code == .ECONNREFUSED
                    } else {
                        refused = false
                    }
                    box.finish(
                        Outcome(
                            state: refused ? .closed : .filtered,
                            milliseconds: nil,
                            detail: refused
                                ? "UDP port unreachable"
                                : "No UDP response (open|filtered)"
                        ))
                    connection.cancel()
                case .cancelled:
                    box.finish(
                        Outcome(
                            state: .filtered, milliseconds: nil,
                            detail: "No UDP response (open|filtered)"))
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                box.finish(
                    Outcome(
                        state: .filtered, milliseconds: nil,
                        detail: "No UDP response (open|filtered)"))
                connection.cancel()
            }
        }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        private let continuation: CheckedContinuation<Outcome, Never>

        init(continuation: CheckedContinuation<Outcome, Never>) {
            self.continuation = continuation
        }

        func finish(_ outcome: Outcome) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            continuation.resume(returning: outcome)
        }
    }
}
