import Foundation

/// How a supervised child is launched and when it counts as healthy.
struct SupervisedProcessConfiguration {
    let executableURL: URL
    /// Arguments for the nth launch (1-based). A retry gets a fresh set, which
    /// is how a transport path or token is rebound after a failed start.
    var arguments: (Int) -> [String] = { _ in [] }
    var environment: [String: String] = [:]

    /// How long the child may take to answer before the launch is treated as
    /// failed. Readiness is a real answer from the child, never "the process
    /// exists".
    var readinessTimeout: TimeInterval = 6
    /// How often readiness is polled while waiting for that answer.
    var readinessPollInterval: TimeInterval = 0.05

    /// Delay before an automatic restart after an unexpected exit.
    var restartDelay: TimeInterval = 2
    /// Minimum interval between two automatic restarts, so a crashing helper
    /// cannot spin.
    var restartRateLimit: TimeInterval = 60
    /// Grace period between SIGTERM and SIGKILL.
    var terminationGracePeriod: TimeInterval = 2

    /// True once the child is ready to do work (socket connected, port bound,
    /// handshake answered).
    var isReady: () async -> Bool = { true }
    /// A cheap health probe run before an automatic restart. A helper that is
    /// not healthy is not restarted: the environment, not the child, is broken.
    var isHealthy: () async -> Bool = { true }
}

enum SupervisedProcessError: LocalizedError {
    case launchFailed(String)
    case notReady
    case stopped

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return message
        case .notReady: return "The helper process did not become ready in time."
        case .stopped: return "The helper process was stopped."
        }
    }
}

/// A long-lived child process with a readiness probe, one retry on a failed
/// start, a rate-limited automatic restart and an idempotent shutdown.
///
/// The point is that a hung helper stops looking like "no data": launch fails
/// loudly after `readinessTimeout`, a crash restarts once instead of never, a
/// crash loop is throttled, and two callers cannot start two children or kill
/// one twice.
actor SupervisedProcess {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case restarting
        case failed
    }

    private let configuration: SupervisedProcessConfiguration
    private(set) var state: State = .stopped
    private(set) var launchCount = 0

    private var child: Process?
    private var restartTask: Task<Void, Never>?
    private var lastRestartAt: Date?
    private var isStopping = false
    /// Set when the child dies before it ever answered "ready". The launch path
    /// reads it so a process that exits during startup fails the start instead
    /// of being reported as running.
    private var exitedBeforeReady = false

    init(_ configuration: SupervisedProcessConfiguration) {
        self.configuration = configuration
    }

    var isRunning: Bool { child?.isRunning == true }

    /// Launches the child and waits for its readiness answer. Throws when the
    /// child exits early or does not answer within the timeout; in both cases
    /// the child is terminated before the error leaves this call.
    func start() async throws {
        guard state != .running, !isRunning else { return }
        isStopping = false
        try await launch(attempt: 1)
    }

    /// Stops the child and cancels any pending restart. Safe to call twice: the
    /// second call has nothing left to signal.
    func stop() async {
        isStopping = true
        restartTask?.cancel()
        restartTask = nil
        state = .stopped
        guard let process = child else { return }
        child = nil
        await terminate(process)
    }

    /// Restarts on demand, serialised with the automatic restart so two callers
    /// share one launch.
    func restart() async throws {
        await stop()
        try await start()
    }

    // MARK: - Launch

    private func launch(attempt: Int) async throws {
        state = .starting
        launchCount += 1
        exitedBeforeReady = false
        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments(attempt)
        if !configuration.environment.isEmpty {
            process.environment = configuration.environment
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            Task { await self?.childExited(status: finished.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            state = .failed
            throw SupervisedProcessError.launchFailed(error.localizedDescription)
        }
        child = process

        if await waitForReadiness(process) {
            state = .running
            return
        }

        child = nil
        await terminate(process)
        if attempt == 1 {
            // One retry with fresh arguments: the usual failure is a stale
            // transport path or token, which the next attempt rebuilds.
            try await launch(attempt: 2)
            return
        }
        state = .failed
        throw SupervisedProcessError.notReady
    }

    /// Readiness or exit, whichever comes first, within the timeout.
    private func waitForReadiness(_ process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(configuration.readinessTimeout)
        while Date() < deadline {
            if exitedBeforeReady || !process.isRunning { return false }
            if await configuration.isReady() {
                // A readiness signal can race the child's exit; give the
                // termination handler one poll window to be observed before
                // calling this launch successful.
                try? await Task.sleep(
                    nanoseconds: UInt64(max(0.001, configuration.readinessPollInterval) * 1_000_000_000))
                return !exitedBeforeReady && process.isRunning
            }
            try? await Task.sleep(
                nanoseconds: UInt64(max(0.001, configuration.readinessPollInterval) * 1_000_000_000))
        }
        guard !exitedBeforeReady, process.isRunning else { return false }
        return await configuration.isReady()
    }

    // MARK: - Exit and restart

    private func childExited(status: Int32) async {
        if state == .starting {
            exitedBeforeReady = true
            return
        }
        guard !isStopping, state == .running else { return }
        child = nil
        state = .restarting
        scheduleRestart()
    }

    private func scheduleRestart() {
        // One restart in flight: concurrent exits and callers await the same
        // attempt instead of starting several children.
        guard restartTask == nil else { return }
        if let last = lastRestartAt, Date().timeIntervalSince(last) < configuration.restartRateLimit {
            state = .failed
            return
        }
        let delay = configuration.restartDelay
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            await self?.performRestart()
        }
    }

    private func performRestart() async {
        restartTask = nil
        guard !isStopping else { return }
        guard await configuration.isHealthy() else {
            state = .failed
            return
        }
        lastRestartAt = Date()
        do {
            try await launch(attempt: 1)
        } catch {
            state = .failed
        }
    }

    // MARK: - Shutdown

    private func terminate(_ process: Process) async {
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(configuration.terminationGracePeriod)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
