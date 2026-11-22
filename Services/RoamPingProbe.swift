import Foundation
import LanFiCore

/// Pings the default gateway about once a second while a roaming walk test is
/// running. Read-only ICMP from this process; no child process and nothing
/// leaves the local link except the echo requests.
@MainActor
final class RoamPingProbe: ObservableObject {
    static let interval: TimeInterval = 1
    static let timeoutMilliseconds = 700
    static let maximumSamples = 900

    @Published private(set) var samples: [RoamProbeSample] = []
    @Published private(set) var isRunning = false
    @Published private(set) var gateway: String?

    private var task: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        guard let gateway = GatewayGuard.defaultGateway() else {
            self.gateway = nil
            return
        }
        self.gateway = gateway
        isRunning = true
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let at = Date()
                let result = await NativePing.ping(
                    host: gateway, count: 1, timeoutMilliseconds: Self.timeoutMilliseconds)
                let reached = (result?.received ?? 0) > 0
                self.record(
                    RoamProbeSample(
                        at: at, reached: reached,
                        latencyMilliseconds: reached ? result?.averageMilliseconds : nil))
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        samples.removeAll()
    }

    private func record(_ sample: RoamProbeSample) {
        samples.append(sample)
        if samples.count > Self.maximumSamples {
            samples.removeFirst(samples.count - Self.maximumSamples)
        }
    }
}
