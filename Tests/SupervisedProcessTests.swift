import XCTest

final class SupervisedProcessTests: XCTestCase {
    /// `/bin/sh -c <script>` so a test can make a child that exits, hangs or
    /// becomes ready late without shipping a second binary.
    private func makeProcess(
        script: @escaping (Int) -> String,
        readiness: @escaping () async -> Bool = { true },
        timeout: TimeInterval = 0.5,
        restartDelay: TimeInterval = 0.05,
        restartRateLimit: TimeInterval = 0,
        healthy: @escaping () async -> Bool = { true }
    ) -> SupervisedProcess {
        SupervisedProcess(
            SupervisedProcessConfiguration(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: { attempt in ["-c", script(attempt)] },
                readinessTimeout: timeout,
                restartDelay: restartDelay,
                restartRateLimit: restartRateLimit,
                terminationGracePeriod: 0.3,
                isReady: readiness,
                isHealthy: healthy))
    }

    private func waitUntil(
        _ timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }

    func testStartBecomesRunningAndStopIsIdempotent() async throws {
        let process = makeProcess(script: { _ in "sleep 30" })
        try await process.start()
        let running = await process.state
        XCTAssertEqual(running, .running)

        await process.stop()
        await process.stop()
        let stopped = await process.state
        XCTAssertEqual(stopped, .stopped)
        let isRunning = await process.isRunning
        XCTAssertFalse(isRunning)
    }

    func testChildThatExitsImmediatelyFailsTheStart() async {
        let process = makeProcess(script: { _ in "exit 1" })
        do {
            try await process.start()
            XCTFail("a child that exits must not report ready")
        } catch {
            // expected
        }
        let launches = await process.launchCount
        XCTAssertEqual(launches, 2, "one failed launch plus one retry")
        let state = await process.state
        XCTAssertEqual(state, .failed)
    }

    func testReadinessTimeoutRetriesOnceThenFails() async {
        let process = makeProcess(script: { _ in "sleep 30" }, readiness: { false }, timeout: 0.2)
        do {
            try await process.start()
            XCTFail("expected a readiness timeout")
        } catch {
            // expected
        }
        let launches = await process.launchCount
        XCTAssertEqual(launches, 2)
        let isRunning = await process.isRunning
        XCTAssertFalse(isRunning, "the hung child must be killed")
    }

    func testRetryUsesFreshArguments() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-supervised-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let process = makeProcess(
            script: { attempt in
                attempt == 2 ? "touch \(marker.path); sleep 30" : "sleep 30"
            },
            readiness: { FileManager.default.fileExists(atPath: marker.path) },
            timeout: 0.3)
        try await process.start()
        let launches = await process.launchCount
        XCTAssertEqual(launches, 2, "the second attempt receives new arguments")
        await process.stop()
    }

    func testUnexpectedExitRestartsAutomatically() async throws {
        let process = makeProcess(script: { _ in "sleep 0.15" })
        try await process.start()
        let restarted = await waitUntil { await process.launchCount >= 2 }
        XCTAssertTrue(restarted, "a crashed child is restarted once")
        await process.stop()
    }

    func testRestartRateLimitStopsACrashLoop() async throws {
        let process = makeProcess(script: { _ in "sleep 0.1" }, restartRateLimit: 60)
        try await process.start()
        _ = await waitUntil { await process.launchCount >= 2 }
        // Give a second exit time to happen; the rate limit must block it.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let launches = await process.launchCount
        XCTAssertEqual(launches, 2, "a crash loop is throttled to one restart per minute")
        let state = await process.state
        XCTAssertEqual(state, .failed)
        await process.stop()
    }

    func testUnhealthyHelperIsNotRestarted() async throws {
        let process = makeProcess(script: { _ in "sleep 0.1" }, healthy: { false })
        try await process.start()
        let stopped = await waitUntil { await process.state == .failed }
        XCTAssertTrue(stopped, "an unhealthy environment fails instead of restarting")
        let launches = await process.launchCount
        XCTAssertEqual(launches, 1)
        await process.stop()
    }
}
