import Foundation

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
