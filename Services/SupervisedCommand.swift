import Foundation

struct SupervisedCommandResult: Sendable, Equatable {
    let status: Int32
    let stdout: Data
    let stderr: String
    /// True when the command used most of its allowance before finishing, so a
    /// signal or an empty message can be reported as a timeout rather than a
    /// mysterious failure.
    let timedOut: Bool
}

enum SupervisedCommandError: LocalizedError {
    case launch(String)

    var errorDescription: String? {
        switch self {
        case .launch(let message):
            return message.isEmpty ? "The command could not be started." : message
        }
    }
}

/// One short-lived child whose output matters: ssh, scp, a helper query.
///
/// The child runs under `SupervisedProcess`, so it has a hard run limit and a
/// shutdown that escalates from SIGTERM to SIGKILL. Both pipes are drained
/// while it runs — reading one to end-of-file before the other deadlocks as
/// soon as the child fills the pipe nobody is reading, which is exactly what a
/// few hundred kilobytes of `system_profiler` JSON does.
enum SupervisedCommand {
    static func run(
        _ executable: String, _ arguments: [String], limit: TimeInterval,
        readinessTimeout: TimeInterval = 10
    ) async throws -> SupervisedCommandResult {
        let out = Pipe()
        let errors = Pipe()
        let drainOut = Task<Data, Never> { out.fileHandleForReading.readDataToEndOfFile() }
        let drainErr = Task<Data, Never> { errors.fileHandleForReading.readDataToEndOfFile() }
        let supervised = SupervisedProcess(
            SupervisedProcessConfiguration(
                executableURL: URL(fileURLWithPath: executable), arguments: arguments,
                errorPipe: errors, outputPipe: out, readinessTimeout: readinessTimeout, runLimit: limit,
                terminationGracePeriod: 3))
        let started = Date()
        let status: Int32
        do {
            try await supervised.start()
            status = await supervised.waitUntilExit()
        } catch SupervisedProcessError.exitedBeforeReady(let early) {
            // A one-shot command finishing during startup is an ordinary result.
            status = early
        } catch {
            finishPipes(out: out, errors: errors)
            _ = await drainOut.value
            _ = await drainErr.value
            throw SupervisedCommandError.launch(error.localizedDescription)
        }
        finishPipes(out: out, errors: errors)
        let output = await drainOut.value
        let errorData = await drainErr.value
        let elapsed = Date().timeIntervalSince(started)
        return SupervisedCommandResult(
            status: status, stdout: output,
            stderr: String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            timedOut: elapsed >= limit * 0.5)
    }

    /// The parent holds the write ends too, so a read would never see
    /// end-of-file unless they are closed here.
    private static func finishPipes(out: Pipe, errors: Pipe) {
        out.fileHandleForWriting.closeFile()
        errors.fileHandleForWriting.closeFile()
    }
}
