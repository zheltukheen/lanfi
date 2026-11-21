import Foundation
import SwiftUI
import LanFiCore

// MARK: - Ping

@MainActor
final class PingToolModel: ObservableObject {
    @Published var host = "1.1.1.1"
    @Published var transport: PingTransport = .icmp
    @Published var count = 10
    @Published var continuous = false
    @Published var interval = 0.5
    @Published var portText = "443"
    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?

    var statistics: PingStatistics? {
        samples.isEmpty ? nil : PingStatistics(host: host, samples: samples)
    }

    var port: UInt16? { UInt16(portText) }

    func run() {
        guard !isRunning else { return }
        AnalysisTarget.shared.remember(host)
        guard let target = ToolTarget.parse(host, defaultPort: 443) else {
            errorMessage = "Enter a host name or address."
            return
        }
        guard transport == .icmp || (port ?? 0) > 0 else {
            errorMessage = "Enter a TCP port between 1 and 65535."
            return
        }
        errorMessage = nil
        samples = []
        isRunning = true

        let probe: any PingProbing =
            transport == .icmp ? ICMPPingProbe() : TCPPingProbe(port: port ?? 443)
        let service = PingService(probe: probe)
        let total = continuous ? 10_000 : count
        let delay = interval
        task = Task { [weak self] in
            guard let self else { return }
            for await sample in service.stream(
                host: target.host, count: total, interval: delay)
            {
                self.samples.append(sample)
            }
            self.isRunning = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        stop()
        samples = []
        errorMessage = nil
    }
}
