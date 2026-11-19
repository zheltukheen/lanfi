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
    /// The classic screen's controls, kept so the merged view can do everything
    /// Traceroute could: probe count, per-probe timeout and PTR names.
    @Published var probes = 1
    @Published var waitSeconds = 2
    @Published var resolveNames = true
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
        AnalysisTarget.shared.remember(host)
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
                // Same runner and probe strategy as the plain Traceroute screen:
                // one implementation, so both screens agree on a host.
                let report = try await SystemTracerouteRunner().trace(
                    host: targetHost, maxHops: limit, waitSeconds: self.waitSeconds,
                    probes: self.probes, resolveNames: self.resolveNames)
                if Task.isCancelled { return }
                self.hops = report.hops.map { VisualTracerouteHop(hop: $0, geo: nil) }
                for hop in report.hops where hop.address != nil {
                    guard let address = hop.address,
                        VisualTracerouteFilter.isPublic(address)
                    else { continue }
                    self.locate(address: address, ttl: hop.ttl)
                }
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

    /// Plain-text route, identical in shape to the Traceroute screen's copy.
    var copyText: String {
        var lines = ["LanFi traceroute \(host)", ""]
        for hop in hops {
            let location = [hop.geo?.city, hop.geo?.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            let latency = hop.hop.averageMilliseconds.map { String(format: "%.1f ms", $0) } ?? ""
            lines.append(
                "\(hop.id)\t\(hop.hop.address ?? "*")\t\(hop.hop.hostname ?? "")\t\(latency)\t\(location)"
            )
        }
        return lines.joined(separator: "\n")
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
