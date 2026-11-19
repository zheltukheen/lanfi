import Foundation
import LanFiCore

/// P3.1 — read-only listener inventory plus the watcher behind the
/// "Watch listeners" toggle.
enum ListenerWatchService {
    /// `lsof` is cheap but not free; one sample every 30 s is enough to catch a
    /// server being started without flooding the notification center.
    static let sampleInterval: TimeInterval = 30

    /// TCP listeners plus every UDP socket, which is the set that can answer a
    /// client. The same read-only `lsof` call, no shell, no privileges.
    static func fetchListeners() async throws -> [ListenerSummary] {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-iUDP"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            return OpenConnectionsParser.parse(output).compactMap(ListenerSummary.init(connection:))
        }.value
    }
}

/// Samples the listener set on a timer, diffs consecutive samples and posts one
/// notification per new or closed listener.
///
/// The first sample after starting is a baseline, never a burst of "new
/// listener" alerts for everything the Mac was already running.
@MainActor
final class ListenerWatcher: ObservableObject {
    static let shared = ListenerWatcher()

    @Published private(set) var listeners: [ListenerSummary] = []
    @Published private(set) var changes: [ListenerChange] = []
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSampling = false
    @Published private(set) var isWatching = false

    private var timer: Timer?
    private var isSampleInFlight = false
    private var hasBaseline = false

    private let post: @MainActor (String, String, String) -> Void

    init(
        post: @escaping @MainActor (String, String, String) -> Void = { title, body, id in
            MonitorNotifier.shared.post(title: title, body: body, identifier: id)
        }
    ) {
        self.post = post
    }

    deinit {
        timer?.invalidate()
    }

    var lanReachable: [ListenerSummary] {
        listeners.filter { $0.exposure.isLANReachable }
    }

    var udpCount: Int { listeners.filter { $0.transport == "UDP" }.count }

    /// Applies the persisted toggle when the Connections screen appears.
    func restoreFromSettings() {
        let watching = AppSettingsStore.shared.settings.automation.listenerWatch
        isWatching = watching
        if watching { start() }
    }

    func setWatching(_ watching: Bool) {
        isWatching = watching

        var settings = AppSettingsStore.shared.settings
        if settings.automation.listenerWatch != watching {
            settings.automation.listenerWatch = watching
            AppSettingsStore.shared.save(settings)
        }

        if watching {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard timer == nil else { return }
        hasBaseline = false
        schedule()
        Task { await sample() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hasBaseline = false
    }

    func sampleNow() async {
        await sample()
    }

    func clearChanges() {
        changes.removeAll()
    }

    // MARK: - Sampling

    private func schedule() {
        let timer = Timer(timeInterval: ListenerWatchService.sampleInterval, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = ListenerWatchService.sampleInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() async {
        guard !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }

        do {
            let current = try await ListenerWatchService.fetchListeners()
            let at = Date()
            let detected =
                hasBaseline
                ? ListenerWatchDiff.changes(previous: listeners, current: current, at: at)
                : []

            listeners = current
            lastSampleAt = at
            errorMessage = nil
            hasBaseline = true

            guard !detected.isEmpty else { return }
            changes = Array((detected + changes).prefix(50))
            for change in detected {
                post(change.notificationTitle, change.notificationBody, "listener-\(change.id)")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
