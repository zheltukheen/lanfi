import Foundation

extension Notification.Name {
    /// Findings from the background guards. `MonitorViewModel` folds them into
    /// its event log, so the guards stay independent of the monitor's lifetime.
    static let lanFiSecurityEvent = Notification.Name("LanFi.securityEvent")
}

/// One place that turns a guard finding into a monitor event, so both guards
/// post the same shape and `MonitorViewModel` keeps one channel to read.
enum SecurityEvent {
    static func post(
        _ kind: MonitorEventKind, subject: String, detail: String, bssid: String = ""
    ) {
        let event = MonitorEvent(
            at: Date(), kind: kind, bssid: bssid, ssid: subject, detail: detail)
        NotificationCenter.default.post(
            name: .lanFiSecurityEvent, object: nil, userInfo: ["event": event])
    }
}

/// One-shot read from a command-line tool, off the main actor, shared by the
/// guards and the terminal launcher. Failure is an empty output: every caller
/// treats "no answer" as "nothing to report".
enum ShellOutput {
    static func run(_ path: String, _ arguments: [String]) async -> String {
        let data = await Task.detached(priority: .utility) { () -> Data in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return Data() }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return data
        }.value
        return String(decoding: data, as: UTF8.self)
    }
}

/// Timer and in-flight bookkeeping shared by the polling security guards.
///
/// Both guards ask a system table a question on a fixed interval and publish
/// one snapshot per successful pass; only the question itself differs, so it
/// lives in `performSample()` and the rest lives here.
@MainActor
class PollingGuard: ObservableObject {
    let interval: TimeInterval

    @Published private(set) var isSampling = false
    @Published private(set) var lastCheckedAt: Date?

    private var timer: Timer?
    private var isSampleInFlight = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    deinit {
        timer?.invalidate()
    }

    var isEnabled: Bool { true }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.sample() }
        }
        timer.tolerance = interval * 0.25
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

    private func sample() async {
        guard isEnabled, !isSampleInFlight else { return }
        isSampleInFlight = true
        isSampling = true
        defer {
            isSampling = false
            isSampleInFlight = false
        }
        await performSample()
        lastCheckedAt = Date()
    }

    /// The guard's question. Override; the base class handles cadence, overlap
    /// and the published sampling flags.
    func performSample() async {}
}
