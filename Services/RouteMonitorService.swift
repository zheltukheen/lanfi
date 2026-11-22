import Foundation
import LanFiCore

/// P3.2 — one continuous traceroute target, kept as a rolling window of
/// `MTRService` rounds.
///
/// There is exactly one instance (`shared`) for the whole app: the screen, the
/// menu-bar sparkline and the notifications all read the same window, so a
/// second monitor cannot quietly double the probe traffic. The cadence slows
/// down when the screen is closed and slows further in the background; a round
/// is one `traceroute -q 1` run, never more than one per second.
@MainActor
final class RouteMonitor: ObservableObject {
    static let shared = RouteMonitor()

    static let windowCapacity = 180
    static let eventCapacity = 20
    static let fallbackTarget = "1.1.1.1"
    static let maxHops = 20

    @Published private(set) var samples: [RouteSample] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isSampling = false
    @Published private(set) var target = ""
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var routeChanges: [RouteChange] = []
    @Published private(set) var thresholdCrossings: [RouteThresholdCrossing] = []

    @Published var settings: RouteMonitorSettings {
        didSet {
            let normalized = settings.normalized
            if normalized != settings {
                settings = normalized
                return
            }
            persistSettings()
        }
    }

    private let traceroute: any TracerouteRunning
    private let post: @MainActor (String, String, String) -> Void
    private var task: Task<Void, Never>?
    /// Bumped on every start and stop. A loop only owns the published state
    /// while its generation is still current, so a finishing old loop (its
    /// `defer`) cannot mark a newly started monitor as stopped.
    private var generation = 0
    private var changeDetector = RouteChangeDetector()
    private var thresholdTracker = RouteThresholdTracker()
    private var isApplicationActive = true
    private var isPanelVisible = true

    init(
        traceroute: any TracerouteRunning = SystemTracerouteRunner(),
        post: @escaping @MainActor (String, String, String) -> Void = { title, body, id in
            MonitorNotifier.shared.post(title: title, body: body, identifier: id)
        }
    ) {
        self.traceroute = traceroute
        self.post = post
        settings = Self.loadSettings()
    }

    // MARK: - Lifecycle

    /// Starts the single monitor. Asking for the target that is already running
    /// keeps the existing window instead of starting a second loop.
    func start(host: String? = nil) {
        let requested = (host ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = requested.isEmpty ? (target.isEmpty ? Self.fallbackTarget : target) : requested
        guard let parsed = ToolTarget.parse(resolved) else {
            errorMessage = String(localized: "Enter a host name or address.")
            return
        }
        if isRunning, parsed.host == target { return }

        stop()
        target = parsed.host
        errorMessage = nil
        samples = []
        routeChanges = []
        thresholdCrossings = []
        lastSampleAt = nil
        changeDetector.reset()
        thresholdTracker.reset()
        isRunning = true
        generation += 1
        let current = generation
        task = Task { [weak self] in
            await self?.runLoop(generation: current)
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
        isRunning = false
        isSampling = false
    }

    func clear() {
        stop()
        samples = []
        routeChanges = []
        thresholdCrossings = []
        lastSampleAt = nil
        errorMessage = nil
        changeDetector.reset()
        thresholdTracker.reset()
    }

    /// Closing the screen keeps the monitor running at the slower cadence.
    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
    }

    var cadence: TimeInterval {
        RouteMonitorCadence.interval(
            isApplicationActive: isApplicationActive, isPanelVisible: isPanelVisible)
    }

    // MARK: - Sampling

    private func runLoop(generation: Int) async {
        defer {
            if self.generation == generation {
                isRunning = false
                isSampling = false
            }
        }
        while !Task.isCancelled {
            await sampleOnce(generation: generation)
            if Task.isCancelled { break }
            do {
                try await Task.sleep(nanoseconds: UInt64(cadence * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    private func sampleOnce(generation: Int) async {
        guard isRunning, self.generation == generation, !target.isEmpty else { return }
        isSampling = true
        defer {
            if self.generation == generation { isSampling = false }
        }

        let service = MTRService(runner: traceroute)
        do {
            let report = try await service.run(
                host: target, rounds: 1, maxHops: Self.maxHops, waitSeconds: 1
            ) { _ in }
            guard !Task.isCancelled, self.generation == generation else { return }
            ingest(report)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // A round that fails after the window has data is noise; only an
            // empty window needs the banner.
            if samples.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    func ingest(_ report: MTRReport, at date: Date = Date()) {
        let sample = RouteSample.make(from: report, at: date)
        samples.append(sample)
        if samples.count > Self.windowCapacity {
            samples.removeFirst(samples.count - Self.windowCapacity)
        }
        lastSampleAt = date

        if let change = changeDetector.observe(RoutePath(sample: sample), at: date) {
            routeChanges.insert(change, at: 0)
            if routeChanges.count > Self.eventCapacity {
                routeChanges.removeLast(routeChanges.count - Self.eventCapacity)
            }
            if settings.notifyOnRouteChange {
                notify(
                    body: "\(target): \(change.summary)",
                    identifier: "route-change-\(change.id.uuidString)")
            }
        }

        let stats = RouteHopStatistics.compute(samples: samples)
        let crossings = thresholdTracker.evaluate(stats: stats, settings: settings)
        guard !crossings.isEmpty else { return }
        thresholdCrossings.insert(contentsOf: crossings, at: 0)
        if thresholdCrossings.count > Self.eventCapacity {
            thresholdCrossings.removeLast(thresholdCrossings.count - Self.eventCapacity)
        }
        if settings.notifyOnThreshold {
            for crossing in crossings {
                notify(
                    body: "\(target): \(crossing.summary)",
                    identifier: "route-threshold-\(crossing.id.uuidString)")
            }
        }
    }

    private func notify(body: String, identifier: String) {
        post("LanFi · \(String(localized: "Route monitor"))", body, identifier)
    }

    // MARK: - Settings

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: AppSettingsKey.routeMonitor.rawValue)
    }

    private static func loadSettings() -> RouteMonitorSettings {
        guard
            let data = UserDefaults.standard.data(forKey: AppSettingsKey.routeMonitor.rawValue),
            let decoded = try? JSONDecoder().decode(RouteMonitorSettings.self, from: data)
        else { return RouteMonitorSettings() }
        return decoded.normalized
    }
}
