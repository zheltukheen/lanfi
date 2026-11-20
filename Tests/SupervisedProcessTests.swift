import XCTest

/// The supervisor is exercised through `/bin/sh` children: one that stays,
/// one that exits, one that becomes ready late and one that hangs.
final class SupervisedProcessTests: XCTestCase {
    private func makeProcess(
        script: String,
        readinessTimeout: TimeInterval = 1,
        runLimit: TimeInterval = 30,
        isReady: @escaping @Sendable () async -> Bool = { true }
    ) -> SupervisedProcess {
        SupervisedProcess(
            SupervisedProcessConfiguration(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script],
                readinessTimeout: readinessTimeout,
                readinessPollInterval: 0.02,
                runLimit: runLimit,
                terminationGracePeriod: 0.3,
                isReady: isReady))
    }

    private func marker() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-supervised-\(UUID().uuidString)")
    }

    func testStartAndIdempotentStop() async throws {
        let process = makeProcess(script: "sleep 30")
        try await process.start()
        let running = await process.isRunning
        XCTAssertTrue(running)

        await process.stop()
        await process.stop()
        let stillRunning = await process.isRunning
        XCTAssertFalse(stillRunning)
    }

    func testChildThatExitsDuringStartupFailsTheStart() async {
        let process = makeProcess(script: "exit 1")
        do {
            try await process.start()
            XCTFail("a child that exits must not report ready")
        } catch {
            // expected
        }
        let running = await process.isRunning
        XCTAssertFalse(running)
    }

    func testReadinessTimeoutKillsTheChild() async {
        let process = makeProcess(script: "sleep 30", readinessTimeout: 0.2, isReady: { false })
        do {
            try await process.start()
            XCTFail("expected a readiness timeout")
        } catch {
            // expected
        }
        let running = await process.isRunning
        XCTAssertFalse(running, "a child that never became ready must be killed")
    }

    func testStartWaitsForTheReadinessSignal() async throws {
        let file = marker()
        defer { try? FileManager.default.removeItem(at: file) }
        let process = makeProcess(
            script: "sleep 0.25; touch '\(file.path)'; sleep 30",
            isReady: { FileManager.default.fileExists(atPath: file.path) })
        try await process.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        await process.stop()
    }

    func testWaitUntilExitReturnsTheChildStatus() async throws {
        let process = makeProcess(script: "sleep 0.2; exit 3")
        try await process.start()
        let status = await process.waitUntilExit()
        XCTAssertEqual(status, 3)
    }

    func testRunLimitKillsAChildThatWouldRunForever() async throws {
        let process = makeProcess(script: "sleep 30", runLimit: 0.3)
        try await process.start()
        let started = Date()
        _ = await process.waitUntilExit()
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "the run limit must end the child")
        let running = await process.isRunning
        XCTAssertFalse(running)
    }

    func testStopResumesAWaiterWithTheTerminatedStatus() async throws {
        let process = makeProcess(script: "sleep 30")
        try await process.start()
        let waiter = Task { await process.waitUntilExit() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await process.stop()
        let status = await waiter.value
        XCTAssertNotEqual(status, 0, "a stopped child reports a non-zero status")
    }

    func testStopBeforeStartDoesNothing() async {
        let process = makeProcess(script: "sleep 30")
        await process.stop()
        let running = await process.isRunning
        XCTAssertFalse(running)
    }
}
