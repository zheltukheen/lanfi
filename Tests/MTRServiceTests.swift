import XCTest

final class MTRServiceTests: XCTestCase {

    func testMergesHopsAndComputesLossAndJitter() async throws {
        let runner = ScriptedRunner(reports: [
            report(round: [
                hop(1, "10.0.0.1", 2),
                hop(2, "10.0.0.2", 5),
                hop(3, "203.0.113.9", 10),
            ]),
            report(round: [
                hop(1, "10.0.0.1", 2.5),
                hop(2, nil, nil),
                hop(3, "203.0.113.9", 12),
            ]),
        ])
        let service = MTRService(runner: runner)
        let updates = Counter()
        let result = try await service.run(
            host: "203.0.113.9", rounds: 2, maxHops: 20, waitSeconds: 1
        ) { _ in
            updates.increment()
        }

        XCTAssertEqual(result.rounds, 2)
        XCTAssertEqual(result.hops.map(\.hop), [1, 2, 3])
        XCTAssertEqual(updates.value, 2)

        let first = result.hops[0]
        XCTAssertEqual(first.sent, 2)
        XCTAssertEqual(first.received, 2)
        XCTAssertEqual(first.lossPercent, 0, accuracy: 0.001)
        XCTAssertEqual(first.averageMilliseconds ?? 0, 2.25, accuracy: 0.001)
        XCTAssertEqual(first.jitterMilliseconds ?? 0, 0.25, accuracy: 0.001)

        let second = result.hops[1]
        XCTAssertEqual(second.sent, 2)
        XCTAssertEqual(second.received, 1)
        XCTAssertEqual(second.lossPercent, 50, accuracy: 0.001)

        let third = result.hops[2]
        XCTAssertEqual(third.sent, 2)
        XCTAssertEqual(third.received, 2)
        XCTAssertEqual(third.averageMilliseconds ?? 0, 11, accuracy: 0.001)
    }

    func testShortPathDoesNotCountUnprobedHops() async throws {
        let runner = ScriptedRunner(reports: [
            report(round: [hop(1, "10.0.0.1", 1), hop(2, "10.0.0.2", 2), hop(3, "target", 3)]),
            report(round: [hop(1, "10.0.0.1", 1), hop(2, "10.0.0.2", 2)]),
        ])
        let service = MTRService(runner: runner)
        let result = try await service.run(
            host: "target", rounds: 2, maxHops: 20, waitSeconds: 1
        ) { _ in }

        XCTAssertEqual(result.hops.map(\.sent), [2, 2, 1])
        XCTAssertEqual(result.hops.map(\.received), [2, 2, 1])
    }

    func testAllTimeoutsReportFullLoss() async throws {
        let runner = ScriptedRunner(reports: [
            report(round: [hop(1, nil, nil), hop(2, nil, nil)])
        ])
        let service = MTRService(runner: runner)
        let result = try await service.run(
            host: "unreachable", rounds: 1, maxHops: 20, waitSeconds: 1
        ) { _ in }

        XCTAssertEqual(result.hops.count, 2)
        XCTAssertEqual(result.hops[0].lossPercent, 100, accuracy: 0.001)
        XCTAssertNil(result.hops[0].averageMilliseconds)
        XCTAssertFalse(result.reachedTarget)
    }

    func testFirstRoundFailurePropagates() async {
        let runner = ScriptedRunner(reports: [], error: TracerouteError.unavailable)
        let service = MTRService(runner: runner)
        do {
            _ = try await service.run(
                host: "example.com", rounds: 2, maxHops: 20, waitSeconds: 1
            ) { _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? TracerouteError, .unavailable)
        }
    }

    private func report(round hops: [TracerouteHop]) -> TracerouteReport {
        TracerouteReport(host: "target", hops: hops, startedAt: Date())
    }

    private func hop(_ ttl: Int, _ address: String?, _ milliseconds: Double?) -> TracerouteHop {
        TracerouteHop(
            ttl: ttl,
            address: address,
            milliseconds: milliseconds.map { [$0] } ?? [],
            timedOut: address == nil
        )
    }
}

private actor ScriptedRunner: TracerouteRunning {
    private var reports: [TracerouteReport]
    private var index = 0
    private let error: Error?

    init(reports: [TracerouteReport], error: Error? = nil) {
        self.reports = reports
        self.error = error
    }

    func trace(
        host: String, maxHops: Int, waitSeconds: Int, probes: Int, resolveNames: Bool
    ) async throws -> TracerouteReport {
        if let error { throw error }
        guard index < reports.count else { throw TracerouteError.timedOut }
        defer { index += 1 }
        return reports[index]
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
