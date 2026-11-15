import Foundation
import SwiftUI

// MARK: - Visual traceroute

@MainActor
final class VisualTracerouteToolModel: ObservableObject {
    enum Phase: Equatable {
        case idle, tracing, retrying
    }

    @Published var host = "example.com"
    @Published var maxHops = 20
    @Published private(set) var hops: [VisualTracerouteHop] = []
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var origin: GeoIPReport?
    @Published private(set) var destination: GeoIPReport?
    @Published private(set) var currentAddress: String?
    @Published private(set) var currentMilliseconds: Double?
    @Published private(set) var probe: TracerouteProbe = .icmp
    @Published private(set) var startedAt: Date?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var lookups: [Task<Void, Never>] = []
    private var geoCache: [String: GeoIPReport] = [:]

    var isRunning: Bool { phase != .idle }
    var mappedCount: Int { hops.filter { $0.geo != nil }.count }

    var progress: Double {
        guard maxHops > 0 else { return 0 }
        return min(1, Double(hops.count) / Double(maxHops))
    }

    var currentTTL: Int? {
        guard isRunning else { return nil }
        return hops.last?.id
    }

    func run() {
        guard !isRunning else { return }
        guard let target = ToolTarget.parse(host) else {
            errorMessage = "Enter a host name or address."
            return
        }
        errorMessage = nil
        hops = []
        origin = nil
        destination = nil
        currentAddress = nil
        currentMilliseconds = nil
        startedAt = Date()
        probe = .icmp
        phase = .tracing
        let limit = maxHops
        let targetHost = target.host

        locateOrigin()
        locateDestination(host: targetHost)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.stream(host: targetHost, maxHops: limit, probe: .icmp)
                if Task.isCancelled { return }

                // ICMP replies (or the whole hop list) can be filtered; retry
                // once with the classic UDP probes when nothing came back.
                if self.hops.allSatisfy({ $0.hop.address == nil }) {
                    self.phase = .retrying
                    self.probe = .udp
                    self.hops = []
                    self.currentAddress = nil
                    self.currentMilliseconds = nil
                    try await self.stream(host: targetHost, maxHops: limit, probe: .udp)
                }
                if Task.isCancelled { return }
                self.phase = .idle
                self.currentAddress = nil
                self.currentMilliseconds = nil
                self.task = nil
            } catch is CancellationError {
                self.phase = .idle
                self.task = nil
            } catch {
                self.errorMessage = error.localizedDescription
                self.phase = .idle
                self.task = nil
            }
        }
    }

    private func stream(
        host: String, maxHops: Int, probe: TracerouteProbe
    ) async throws {
        let stream = SystemTracerouteRunner().stream(
            host: host, maxHops: maxHops, waitSeconds: 2, probes: 1,
            resolveNames: false, probe: probe)
        for try await hop in stream {
            if Task.isCancelled { return }
            hops.append(VisualTracerouteHop(hop: hop, geo: nil))
            currentAddress = hop.address
            currentMilliseconds = hop.averageMilliseconds
            if let address = hop.address, VisualTracerouteFilter.isPublic(address) {
                locate(address: address, ttl: hop.ttl)
            }
        }
    }

    private func locateOrigin() {
        lookups.append(
            Task { [weak self] in
                guard let report = try? await GeoIPClient().lookup(nil),
                    !Task.isCancelled
                else { return }
                self?.origin = report
            })
    }

    private func locateDestination(host: String) {
        lookups.append(
            Task { [weak self] in
                guard let report = try? await GeoIPClient().lookup(host),
                    !Task.isCancelled
                else { return }
                self?.destination = report
            })
    }

    private func locate(address: String, ttl: Int) {
        if let cached = geoCache[address] {
            apply(cached, ttl: ttl)
            return
        }
        lookups.append(
            Task { [weak self] in
                guard let self else { return }
                var report = try? await GeoIPClient().lookup(address)
                if report == nil {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    report = try? await GeoIPClient().lookup(address)
                }
                guard let report, !Task.isCancelled else { return }
                self.geoCache[address] = report
                self.apply(report, ttl: ttl)
            })
    }

    private func apply(_ report: GeoIPReport, ttl: Int) {
        guard let index = hops.firstIndex(where: { $0.id == ttl }) else { return }
        hops[index] = VisualTracerouteHop(hop: hops[index].hop, geo: report)
    }

    func stop() {
        task?.cancel()
        lookups.forEach { $0.cancel() }
        lookups = []
        task = nil
        phase = .idle
        currentAddress = nil
        currentMilliseconds = nil
    }

    func clear() {
        stop()
        hops = []
        origin = nil
        destination = nil
        startedAt = nil
        geoCache = [:]
        errorMessage = nil
    }
}
