import Foundation
import LanFiCore
import Network

/// P3.3 — watches connectivity on a timer and from `NWPathMonitor`, keeps the
/// last verdict for the menu bar and notifies on transitions.
///
/// The probe is an ordinary HTTP GET to the captive-portal endpoint, so a
/// captive portal can be told apart from a dead WAN. Nothing is uploaded and
/// the interval slows down while the app is in the background.
@MainActor
final class ConnectivityWatchdog: ObservableObject {
    static let shared = ConnectivityWatchdog()

    static let intervalRange: ClosedRange<Double> = 15...300

    @Published private(set) var verdict: ConnectivityVerdict = .unknown
    @Published private(set) var latencyMilliseconds: Int?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var isChecking = false
    @Published private(set) var isEnabled = false

    private var machine = ConnectivityWatchdogMachine()
    private var policy = ConnectivityAlertPolicy()
    private var settings = AppSettings.ConnectivitySettings()
    private var monitorAlerts = MonitorAlertSettings.default
    private var isApplicationActive = true
    private var pathReachable: Bool?
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var checkTask: Task<Void, Never>?
    private var settingsObserver: NSObjectProtocol?
    private var didRequestAuthorization = false

    private let probe: @Sendable (String) async -> ConnectivityProbeOutcome
    private let post: @MainActor (String, String, String) -> Void

    init(
        probe: @escaping @Sendable (String) async -> ConnectivityProbeOutcome = {
            await ConnectivityHTTPProbe().probe(urlString: $0)
        },
        post: @escaping @MainActor (String, String, String) -> Void = { title, body, id in
            MonitorNotifier.shared.post(title: title, body: body, identifier: id)
        }
    ) {
        self.probe = probe
        self.post = post
    }

    deinit {
        timer?.invalidate()
        pathMonitor?.cancel()
        checkTask?.cancel()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Lifecycle

    func start() {
        reloadSettings()
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.pathChanged(reachable)
            }
        }
        monitor.start(queue: DispatchQueue(label: "ru.zheltukheen.LanFi.connectivity"))
        pathMonitor = monitor

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .lanFiSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reloadSettings() }
        }

        schedule()
        requestAuthorizationIfNeeded()
        Task { await self.checkNow() }
    }

    /// The watchdog slows to one check every `interval × 4` (capped at five
    /// minutes) while LanFi is in the background.
    func setApplicationActive(_ active: Bool) {
        guard active != isApplicationActive else { return }
        isApplicationActive = active
        schedule()
    }

    func checkNow() async {
        guard isEnabled, !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var outcome: ConnectivityProbeOutcome?
        if pathReachable != false {
            let primary = await probe(settings.primaryProbeURL)
            if primary.didFail {
                outcome = await probe(settings.fallbackProbeURL)
            } else {
                outcome = primary
            }
        }

        let now = Date()
        let change = machine.record(pathReachable: pathReachable, probe: outcome, at: now)
        verdict = machine.verdict
        latencyMilliseconds = machine.latencyMilliseconds
        lastCheckedAt = machine.lastCheckedAt

        guard let change,
            policy.shouldNotify(
                change: change, settings: settings, quietHours: monitorAlerts, now: now)
        else { return }

        post(
            "LanFi · \(String(localized: "Connectivity"))",
            change.to.alertBody,
            "connectivity-\(change.to.rawValue)-\(UUID().uuidString)")
    }

    // MARK: - Settings

    private func reloadSettings() {
        let stored = AppSettingsStore.shared.settings
        settings = stored.connectivity
        if let data = UserDefaults.standard.data(forKey: AppSettingsKey.monitorAlerts.rawValue),
            let decoded = try? JSONDecoder().decode(MonitorAlertSettings.self, from: data)
        {
            monitorAlerts = decoded
        }

        isEnabled = settings.enabled
        schedule()
        if isEnabled {
            requestAuthorizationIfNeeded()
            if lastCheckedAt == nil { Task { await self.checkNow() } }
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard isEnabled, !didRequestAuthorization else { return }
        guard settings.notifyOffline || settings.notifyCaptivePortal || settings.notifyRestored
        else { return }
        didRequestAuthorization = true
        Task { _ = await MonitorNotifier.shared.requestAuthorization() }
    }

    // MARK: - Scheduling

    private func pathChanged(_ reachable: Bool) {
        pathReachable = reachable
        Task { await self.checkNow() }
    }

    private var checkInterval: TimeInterval {
        let base = min(
            max(settings.intervalSeconds, Self.intervalRange.lowerBound),
            Self.intervalRange.upperBound)
        return isApplicationActive ? base : min(300, base * 4)
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard isEnabled else {
            checkTask?.cancel()
            checkTask = nil
            return
        }

        let interval = checkInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkNow() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// The default transport: one plain HTTP GET to the captive-portal endpoint.
struct ConnectivityHTTPProbe {
    var timeout: TimeInterval = 8

    func probe(urlString: String) async -> ConnectivityProbeOutcome {
        guard let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return .failure }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = "GET"

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure }
            return ConnectivityProbeOutcome(
                statusCode: http.statusCode,
                redirected: http.url?.host != nil && http.url?.host != url.host,
                body: String(decoding: data.prefix(4096), as: UTF8.self),
                latencyMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
        } catch {
            return .failure
        }
    }
}
