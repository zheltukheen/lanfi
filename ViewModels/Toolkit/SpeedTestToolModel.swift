import Foundation
import SwiftUI

// MARK: - Speed test

@MainActor
final class SpeedTestToolModel: ObservableObject {
    @Published private(set) var report: ThroughputReport?
    @Published private(set) var history: [ThroughputMeasurement] = []
    @Published var schedule: SpeedTestSchedule {
        didSet {
            defaults.set(schedule.rawValue, forKey: Self.scheduleKey)
            startScheduler()
        }
    }
    @Published private(set) var isRunning = false
    @Published var errorMessage: String?

    private static let scheduleKey = "LanFi.speedTestSchedule"
    private let historyStore = ThroughputHistoryStore()
    private let defaults = UserDefaults.standard
    private var task: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?

    init() {
        schedule =
            SpeedTestSchedule(rawValue: defaults.string(forKey: Self.scheduleKey) ?? "") ?? .off
        let loaded = historyStore.load()
        history = loaded
        report = loaded.last?.report
        startScheduler()
    }

    var nextRun: Date? {
        schedule.nextRun(after: history.last?.testedAt)
    }

    var newestFirst: [ThroughputMeasurement] {
        Array(history.reversed())
    }

    func run() {
        guard !isRunning else { return }
        task = Task { [weak self] in
            await self?.measure()
        }
    }

    func measure() async {
        guard !isRunning else { return }
        errorMessage = nil
        isRunning = true
        defer {
            isRunning = false
            task = nil
        }
        do {
            let measured = try await Task.detached(priority: .userInitiated) {
                try await ThroughputTester.run()
            }.value
            report = measured
            record(measured)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        report = nil
        errorMessage = nil
        isRunning = false
    }

    func clearHistory() {
        history.removeAll()
        historyStore.clear()
        report = nil
    }

    private func record(_ report: ThroughputReport) {
        history.append(ThroughputMeasurement(report: report))
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
        historyStore.save(history)
    }

    private func startScheduler() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard schedule != .off else { return }
        scheduleTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if !self.isRunning,
                    self.schedule.isDue(lastRun: self.history.last?.testedAt)
                {
                    self.run()
                }
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
            }
        }
    }
}
