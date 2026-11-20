import Foundation

/// How a supervised child is launched and when it counts as started.
struct SupervisedProcessConfiguration {
    let executableURL: URL
    let arguments: [String]
    var environment: [String: String] = [:]
    /// Stderr sink, when the caller needs the child's message on failure.
    var errorPipe: Pipe?
    /// Stdout sink, when the caller reads the child's output. Nil discards it.
    var outputPipe: Pipe?

    /// How long the child has to show a real sign of life. A helper that never
    /// answers is killed and the start fails instead of hanging the caller.
    var readinessTimeout: TimeInterval = 120
    var readinessPollInterval: TimeInterval = 0.1
    /// Hard limit for the whole run: past it the child is killed, so a stuck
    /// capture or a stuck remote command cannot run forever.
    var runLimit: TimeInterval = 300
    /// Grace between SIGTERM and SIGKILL.
    var terminationGracePeriod: TimeInterval = 2

    /// The child's own readiness signal (a capture file that grows, a port
    /// that answers) — never "the process exists".
    var isReady: @Sendable () async -> Bool = { true }
}

enum SupervisedProcessError: LocalizedError {
    case launchFailed(String)
    case notReady
    case exitedBeforeReady(Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return message
        case .notReady: return "The helper process did not start in time."
        case .exitedBeforeReady(let status): return "The helper process exited with status \(status)."
        }
    }
}

/// A child process the app has to be able to stop: a readiness probe with a
/// deadline, a hard run limit and a shutdown that escalates from SIGTERM to
/// SIGKILL.
///
/// There is no restart policy on purpose. The callers are one-shot by nature
/// (a capture of N seconds, a remote scan); relaunching them behind the user's
/// back would duplicate a capture or a privileged prompt, not repair anything.
actor SupervisedProcess {
    private let configuration: SupervisedProcessConfiguration

    private var child: Process?
    private var exitStatus: Int32?
    private var waiter: CheckedContinuation<Int32, Never>?
    private var deadlineTask: Task<Void, Never>?

    init(_ configuration: SupervisedProcessConfiguration) {
        self.configuration = configuration
    }

    var isRunning: Bool { child?.isRunning == true }

    /// Launches the child and waits for its readiness signal. Throws when it
    /// exits first or does not answer within `readinessTimeout`; in both cases
    /// the child is already stopped when the error is thrown.
    func start() async throws {
        guard child == nil else { return }

        let process = Process()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        if !configuration.environment.isEmpty {
            process.environment = configuration.environment
        }
        process.standardOutput = configuration.outputPipe ?? FileHandle.nullDevice
        process.standardError = configuration.errorPipe
        process.terminationHandler = { [weak self] finished in
            Task { await self?.childExited(status: finished.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            throw SupervisedProcessError.launchFailed(error.localizedDescription)
        }
        child = process

        guard await waitUntilReady(process) else {
            let earlyStatus = exitStatus
            await terminate(process)
            child = nil
            if let earlyStatus { throw SupervisedProcessError.exitedBeforeReady(earlyStatus) }
            throw SupervisedProcessError.notReady
        }
        startDeadline()
    }

    /// Waits for the child to finish and returns its status. The child is
    /// killed when `runLimit` passes first.
    func waitUntilExit() async -> Int32 {
        if let exitStatus { return exitStatus }
        return await withCheckedContinuation { continuation in
            if let exitStatus {
                continuation.resume(returning: exitStatus)
            } else {
                waiter = continuation
            }
        }
    }

    /// Stops the child if it is still running. Safe to call twice and after
    /// the child has already exited.
    func stop() async {
        deadlineTask?.cancel()
        deadlineTask = nil
        guard let process = child else { return }
        await terminate(process)
    }

    // MARK: - Internals

    private func waitUntilReady(_ process: Process) async -> Bool {
        let deadline = Date().addingTimeInterval(configuration.readinessTimeout)
        let poll = UInt64(max(0.01, configuration.readinessPollInterval) * 1_000_000_000)
        while Date() < deadline {
            if !process.isRunning { return false }
            if await configuration.isReady() {
                // The readiness signal can win the race against an exit; let
                // the termination handler be observed before trusting it.
                try? await Task.sleep(nanoseconds: poll)
                return process.isRunning
            }
            try? await Task.sleep(nanoseconds: poll)
        }
        return false
    }

    private func startDeadline() {
        let limit = configuration.runLimit
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, limit) * 1_000_000_000))
            await self?.deadlineReached()
        }
    }

    private func deadlineReached() async {
        deadlineTask = nil
        guard let process = child else { return }
        await terminate(process)
    }

    private func childExited(status: Int32) async {
        exitStatus = status
        child = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        waiter?.resume(returning: status)
        waiter = nil
    }

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
