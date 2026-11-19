import AppKit
import Foundation

/// Drives the menu-bar live meter: samples the primary and Wi-Fi interface
/// counters, keeps the last 60 smoothed samples for the sparkline and caches the
/// optional public-IP lookup.
@MainActor
final class MenuBarMeterModel: ObservableObject {
    /// The one meter the app samples with. Views that can be built outside the
    /// main window (previews, snapshots, smoke tests) read it too, so the
    /// dashboard never needs a second sampler just to show a number.
    static let shared = MenuBarMeterModel()

    static let sampleCapacity = 60

    @Published private(set) var samples: [Double] = []
    @Published private(set) var rates: [MenuBarThroughput] = []
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var publicIP: String?
    @Published private(set) var publicCountry: String?
    @Published private(set) var publicIPError: String?
    @Published private(set) var isLookingUpPublicIP = false

    private let reader = ThroughputCounterReader()
    private var timer: Timer?
    private var previous: [String: (counters: InterfaceCounters, at: Date)] = [:]
    private var smoothers: [String: ThroughputSmoother] = [:]
    private var isApplicationActive = true
    private var geoTask: Task<Void, Never>?

    var primaryRate: MenuBarThroughput? {
        rates.first { $0.tone == "primary" } ?? rates.first
    }

    /// Test seam: lets the meter be exercised without a run loop.
    var sampleInterval: TimeInterval { isApplicationActive ? 2 : 30 }

    deinit {
        timer?.invalidate()
        geoTask?.cancel()
    }

    func start() {
        guard timer == nil else { return }
        sample()
        schedule()
    }

    /// The sampler slows to one tick every 30 s while the app is inactive, so
    /// an idle Mac does not pay for a 2 s timer.
    func setApplicationActive(_ active: Bool) {
        guard active != isApplicationActive else { return }
        isApplicationActive = active
        schedule()
    }

    func refreshPublicIP() {
        guard geoTask == nil else { return }
        isLookingUpPublicIP = true
        publicIPError = nil
        geoTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isLookingUpPublicIP = false
                self.geoTask = nil
            }
            do {
                let report = try await GeoIPClient().lookup(nil)
                self.publicIP = report.ip
                self.publicCountry = report.country.isEmpty ? report.countryCode : report.country
            } catch {
                self.publicIPError = error.localizedDescription
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        let timer = Timer(timeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer.tolerance = sampleInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        let now = Date()
        var names = Set<String>()
        let primary = reader.primaryInterfaceName()
        let wifi = reader.wifiInterfaceName()
        if let primary { names.insert(primary) }
        if let wifi { names.insert(wifi) }
        let counters = reader.counters(for: names)
        guard !counters.isEmpty else {
            lastSampleAt = now
            return
        }

        var orderedNames: [String] = []
        for name in [primary, wifi].compactMap({ $0 }) where !orderedNames.contains(name) {
            orderedNames.append(name)
        }

        var rows: [MenuBarThroughput] = []
        for name in orderedNames where counters[name] != nil {
            guard let current = counters[name] else { continue }
            var smoother = smoothers[name] ?? ThroughputSmoother(alpha: 0.4)
            defer { smoothers[name] = smoother }

            if let previousEntry = previous[name],
                let raw = ThroughputRate.sample(
                    previous: previousEntry.counters,
                    previousAt: previousEntry.at,
                    current: current,
                    now: now
                )
            {
                let smoothed = smoother.add(raw)
                rows.append(
                    MenuBarThroughput(
                        interfaceName: name,
                        tone: name == primary ? "primary" : "wifi",
                        receivedBytesPerSecond: smoothed.receivedBytesPerSecond,
                        sentBytesPerSecond: smoothed.sentBytesPerSecond
                    ))
            } else {
                rows.append(
                    MenuBarThroughput(
                        interfaceName: name,
                        tone: name == primary ? "primary" : "wifi",
                        receivedBytesPerSecond: 0,
                        sentBytesPerSecond: 0
                    ))
            }
            previous[name] = (current, now)
        }

        rates = rows
        lastSampleAt = now
        if let total = rows.first?.totalBytesPerSecond {
            samples.append(total)
            if samples.count > Self.sampleCapacity {
                samples.removeFirst(samples.count - Self.sampleCapacity)
            }
        }
    }
}
