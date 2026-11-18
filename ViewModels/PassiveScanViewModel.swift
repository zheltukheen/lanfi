import LanFiCore
import Combine
import Foundation

/// Owns the scan-mode selection, the channel plan preview and the passive run.
/// Live results are handed back through `onNetworks`, so the analyzer table
/// stays the single place networks are merged.
@MainActor
final class PassiveScanViewModel: ObservableObject {
    @Published var mode: ScanMode = .active {
        didSet { rebuildPlan() }
    }
    @Published var dwellMilliseconds: Double = Double(
        ScanChannelPlanner.defaultDwellMilliseconds)
    {
        didSet { rebuildPlan() }
    }
    @Published var directedSelection: Set<String> = [] {
        didSet { rebuildPlan() }
    }

    @Published private(set) var capabilities: ScanModeCapabilities
    @Published private(set) var supportedChannels: [SupportedChannel]
    @Published private(set) var plan: ScanChannelPlan
    @Published private(set) var progress: PassiveScanProgress?
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false
    @Published private(set) var lastSummary: String?
    @Published private(set) var lastNotes: [String] = []
    @Published var errorMessage: String?

    var onNetworks: (([NetworkModel]) -> Void)?

    private let engine = PassiveScanEngine()
    private let dwellKey = AppSettingsKey.scanDwellMilliseconds.rawValue
    private var task: Task<Void, Never>?

    init() {
        let profile = ScanHardwareProbe.current()
        let channels = SpectrumCapabilities.current()
        let stored = UserDefaults.standard.integer(forKey: dwellKey)
        let dwell =
            stored > 0
            ? stored
            : ScanChannelPlanner.defaultDwellMilliseconds
        capabilities = ScanModeCapabilities.evaluate(profile: profile)
        supportedChannels = channels
        plan = ScanChannelPlanner.plan(
            mode: .active, supported: channels, dwellMilliseconds: dwell, profile: profile)
        directedSelection = Self.defaultDirectedSelection(in: channels)
        rebuildPlan()
    }

    var support: ScanModeSupport { capabilities.support(for: mode) }

    var canStart: Bool {
        mode != .active && !isRunning && support.isUsable && !plan.isEmpty
    }

    var totalDurationLabel: String {
        let seconds = plan.totalDuration
        guard seconds > 0 else { return String(localized: "Instant") }
        return String(format: "%.1f s", seconds)
    }

    func selectMode(_ newMode: ScanMode) {
        guard !isRunning else { return }
        mode = newMode
    }

    /// Re-reads hardware and channels; called when the sheet opens so a docked
    /// Wi-Fi adapter or a macOS change is picked up.
    func refreshHardware() {
        guard !isRunning else { return }
        let profile = ScanHardwareProbe.current()
        capabilities = ScanModeCapabilities.evaluate(profile: profile)
        supportedChannels = SpectrumCapabilities.current()
        if directedSelection.isEmpty {
            directedSelection = Self.defaultDirectedSelection(in: supportedChannels)
        }
        rebuildPlan()
    }

    func toggleDirected(_ item: ScanChannelPlanItem) {
        guard !isRunning else { return }
        if directedSelection.contains(item.id) {
            directedSelection.remove(item.id)
        } else {
            directedSelection.insert(item.id)
        }
    }

    func selectAllDirected(in band: WiFiBand?) {
        guard !isRunning else { return }
        let ids = Set(
            supportedChannels
                .filter { band == nil || $0.band == band }
                .map(\.id))
        if ids.isSubset(of: directedSelection) {
            directedSelection.subtract(ids)
        } else {
            directedSelection.formUnion(ids)
        }
    }

    func clearDirected() {
        guard !isRunning else { return }
        directedSelection.removeAll()
    }

    func start() {
        guard canStart else { return }
        let plan = self.plan
        UserDefaults.standard.set(Int(dwellMilliseconds), forKey: dwellKey)
        errorMessage = nil
        lastSummary = nil
        lastNotes = []
        isCancelling = false
        isRunning = true
        progress = PassiveScanProgress(
            phase: .preparing, completed: 0, total: plan.items.count,
            channel: plan.items.first)

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.engine.scan(plan: plan) { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update
                    }
                }
                if Task.isCancelled {
                    self.lastSummary = String(localized: "Passive scan cancelled.")
                } else {
                    self.onNetworks?(result.networks)
                    self.lastSummary = result.summary
                    self.lastNotes = result.notes
                }
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.isRunning = false
            self.isCancelling = false
            self.task = nil
        }
    }

    func cancel() {
        guard isRunning else { return }
        isCancelling = true
        task?.cancel()
    }

    private func rebuildPlan() {
        let dwell = Int(dwellMilliseconds.rounded())
        plan = ScanChannelPlanner.plan(
            mode: mode,
            supported: supportedChannels,
            dwellMilliseconds: dwell,
            directedChannels: directedSelection,
            profile: capabilities.profile
        )
    }

    private static func defaultDirectedSelection(in channels: [SupportedChannel]) -> Set<String> {
        let sixGHzPSC = channels.filter {
            $0.band == .band6
                && NetworkModel.preferredScanningChannels6GHz.contains($0.channel)
        }
        if !sixGHzPSC.isEmpty {
            return Set(sixGHzPSC.prefix(3).map(\.id))
        }
        let fiveGHz = channels.filter { $0.band == .band5 && $0.channel == 36 }
        if let first = fiveGHz.first { return [first.id] }
        return Set(channels.prefix(1).map(\.id))
    }
}
