import XCTest

/// The remote capture runs ssh through `SupervisedProcess`. These tests use a
/// shell instead of ssh so the timeout and the stderr reporting are checked
/// without a sensor.
final class RemoteCaptureSupervisionTests: XCTestCase {
    func testSuccessfulCommandDoesNotThrow() async throws {
        try await RemoteCaptureService.run("/bin/sh", ["-c", "exit 0"], limit: 10)
    }

    func testFailureCarriesTheChildStderr() async {
        do {
            try await RemoteCaptureService.run(
                "/bin/sh", ["-c", "echo boom >&2; exit 3"], limit: 10)
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("boom"),
                "the child's message should reach the user: \(error.localizedDescription)")
        }
    }

    func testAHangingCommandIsStoppedAtTheLimit() async {
        let started = Date()
        do {
            try await RemoteCaptureService.run("/bin/sh", ["-c", "sleep 30"], limit: 0.6)
            XCTFail("expected a timeout")
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 8, "the child must not run to completion, took \(elapsed)s")
            XCTAssertTrue(
                error.localizedDescription.contains("did not finish in time"),
                "timeouts should say so: \(error.localizedDescription)")
        }
    }

    func testMissingExecutableFailsInsteadOfHanging() async {
        do {
            try await RemoteCaptureService.run("/nonexistent/lanfi-helper", [], limit: 5)
            XCTFail("expected a launch failure")
        } catch {
            XCTAssertTrue(
                (error as? RemoteSensorError) != nil, "the failure should be a sensor error")
        }
    }

    // MARK: - Output capture

    func testStdoutIsReturnedWhileStderrIsSeparate() async throws {
        let result = try await SupervisedCommand.run(
            "/bin/sh", ["-c", "printf hello; echo oops >&2"], limit: 10)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "hello")
        XCTAssertEqual(result.stderr, "oops")
    }

    /// The old code read stderr to end-of-file before stdout, which deadlocks
    /// once the child fills the pipe nobody is reading.
    func testLargeOutputOnBothStreamsDoesNotDeadlock() async throws {
        let result = try await SupervisedCommand.run(
            "/bin/sh", ["-c", "yes lanfi | head -c 400000; yes oops | head -c 400000 >&2"],
            limit: 20)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.count, 400_000)
        // stderr is trimmed, so only the bulk is checked here.
        XCTAssertGreaterThan(result.stderr.count, 390_000)
    }
}
