import AppKit
import Foundation
import LanFiCore
import SystemConfiguration
import UniformTypeIdentifiers

/// P2 — accumulates per-interface byte counters into day/week/month/total
/// volumes and keeps the ledger next to the other local stores.
@MainActor
final class TrafficAccounting: ObservableObject {
    static let shared = TrafficAccounting()
    static let pollInterval: TimeInterval = 60

    @Published private(set) var ledger: TrafficLedger = .empty
    @Published private(set) var lastSampleAt: Date?

    private let sampler = ThroughputCounterReader()
    private var previous: [String: InterfaceCounters] = [:]
    private var timer: Timer?
    private var isSampleInFlight = false

    private var fileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
        return support.appendingPathComponent("traffic-accounting.json")
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        load()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = Self.pollInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func sampleNow() async {
        await sample()
    }

    var volumes: [String: TrafficVolume] {
        ledger.perInterface
    }

    func volume(_ range: TrafficRange) -> TrafficVolume {
        ledger.volume(for: range)
    }

    func reset() {
        ledger = .empty
        save()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi-traffic.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ledger.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Sampling

    private func sample() async {
        guard !isSampleInFlight else { return }
        isSampleInFlight = true
        defer { isSampleInFlight = false }

        var names = await Self.ethernetInterfaces()
        if let primary = sampler.primaryInterfaceName() { names.insert(primary) }
        if let wifi = WiFiInterfaceCatalog.activeName() { names.insert(wifi) }
        guard !names.isEmpty else { return }

        let counters = sampler.counters(for: names)
        let now = Date()
        for (name, current) in counters {
            guard let previous = previous[name] else {
                self.previous[name] = current
                continue
            }
            // A counter that went backwards is a reset (flap, sleep/wake).
            let received =
                current.receivedBytes >= previous.receivedBytes
                ? current.receivedBytes - previous.receivedBytes : 0
            let sent =
                current.sentBytes >= previous.sentBytes
                ? current.sentBytes - previous.sentBytes : 0
            ledger.record(received: received, sent: sent, interface: name, at: now)
            self.previous[name] = current
        }
        lastSampleAt = now
        ledger.prune(now: now)
        save()
    }

    private static func ethernetInterfaces() async -> Set<String> {
        let output = await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            process.arguments = ["-listallhardwareports"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
        return Set(
            LinkAutomationClassifier.ethernetPorts(HardwarePortsOutput.parse(output)).map(\.device))
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(TrafficLedger.self, from: data)
        else { return }
        ledger = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
