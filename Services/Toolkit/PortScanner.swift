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
        let unique = Array(Set(ports)).sorted()
        guard !unique.isEmpty else { return [] }
        let width = max(1, min(concurrency, 64))
        var results: [PortScanResult] = []
        results.reserveCapacity(unique.count)

        for start in stride(from: 0, to: unique.count, by: width) {
            if Task.isCancelled { break }
            let end = min(start + width, unique.count)
            let batch = Array(unique[start..<end])
            await withTaskGroup(of: PortScanResult.self) { group in
                for port in batch {
                    group.addTask {
                        await probe.probe(host: host, port: port, timeout: timeout)
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }
        }
        return results.sorted { $0.port < $1.port }
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
