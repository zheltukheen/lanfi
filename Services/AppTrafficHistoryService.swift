import AppKit
import Foundation
import LanFiCore
import UniformTypeIdentifiers

/// P3.6 — samples the per-process `nettop` deltas on a slow cadence and keeps a
/// week of hourly, per-app byte totals in `app-traffic-history.json`.
///
/// It only runs while the user has enabled Process Traffic (the same opt-in),
/// and it stores byte counts only: no domain, URL or payload.
@MainActor
final class AppTrafficHistoryModel: ObservableObject {
    static let shared = AppTrafficHistoryModel()
    static let sampleInterval: TimeInterval = 300

    @Published private(set) var history: AppTrafficHistory = .empty
    @Published private(set) var isSampling = false
    @Published private(set) var lastSampleAt: Date?

    private var timer: Timer?
    private var isSampleInFlight = false

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("app-traffic-history.json")
    }

    /// Same opt-in switch the Process Traffic screen uses.
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKey.processTrafficEnabled.rawValue)
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        load()
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = Self.sampleInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var topAppsToday: [(app: String, volume: TrafficVolume)] {
        history.topApps()
    }

    var todayTotal: TrafficVolume {
        history.dayTotal()
    }

    func reset() {
        history = .empty
        save()
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "LanFi-app-traffic.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? history.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Sampling

    func sampleNow() async {
        await sample()
    }

    private func sample() async {
        guard isEnabled, !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }

        guard let deltas = try? await ProcessTrafficService.sample(interval: 3) else { return }
        let now = Date()
        history.record(deltas, at: now, excludingPIDs: [Int(ProcessInfo.processInfo.processIdentifier)])
        history.prune(now: now)
        lastSampleAt = now
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(AppTrafficHistory.self, from: data)
        else { return }
        history = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
