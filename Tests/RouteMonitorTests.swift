import XCTest
import LanFiCore

final class RouteMonitorTests: XCTestCase {

    // MARK: - Samples

    func testReportBecomesSampleWithDestinationLatency() {
        let sample = RouteSample.make(
            from: report([
                hop(1, "10.0.0.1", 2),
                hop(2, "203.0.113.9", 14),
            ]),
            at: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(sample.hops.map(\.hop), [1, 2])
        XCTAssertEqual(sample.destination?.address, "203.0.113.9")
        XCTAssertEqual(sample.destinationLatencyMilliseconds ?? 0, 14, accuracy: 0.001)
        XCTAssertTrue(sample.destinationReached)
    }

    func testTimedOutDestinationIsNotReached() {
        let sample = RouteSample.make(
            from: report([hop(1, "10.0.0.1", 2), hop(2, nil, nil)]))

        XCTAssertFalse(sample.destinationReached)
        XCTAssertNil(sample.destinationLatencyMilliseconds)
        XCTAssertEqual(sample.hop(2)?.didReply, false)
    }

    // MARK: - Statistics

    func testLossIsComputedOverTheWindowNotPerRound() {
        let samples = [
            RouteSample.make(from: report([hop(1, "10.0.0.1", 10), hop(2, "203.0.113.9", 20)])),
            RouteSample.make(from: report([hop(1, "10.0.0.1", 12), hop(2, nil, nil)])),
            RouteSample.make(from: report([hop(1, "10.0.0.1", 14), hop(2, "203.0.113.9", 30)])),
        ]

        let stats = RouteHopStatistics.compute(samples: samples)
        XCTAssertEqual(stats.map(\.hop), [1, 2])
        XCTAssertEqual(stats[0].lossPercent, 0, accuracy: 0.001)
        XCTAssertEqual(stats[0].averageMilliseconds ?? 0, 12, accuracy: 0.001)

        XCTAssertEqual(stats[1].attempts, 3)
        XCTAssertEqual(stats[1].replies, 2)
        XCTAssertEqual(stats[1].lossPercent, 100.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stats[1].averageMilliseconds ?? 0, 25, accuracy: 0.001)
    }

    // MARK: - Route change

    func testFirstPathIsTheBaselineAndDoesNotEmitAnEvent() {
        var detector = RouteChangeDetector()
        XCTAssertNil(detector.observe(path([1: "a", 2: "b"]), at: Date()))
        XCTAssertNil(detector.observe(path([1: "a", 2: "b"]), at: Date()))
        XCTAssertEqual(detector.confirmed, path([1: "a", 2: "b"]))
    }

    func testSingleFlapDoesNotEmitAndAConfirmedChangeDoes() {
        var detector = RouteChangeDetector()
        _ = detector.observe(path([1: "a", 2: "b", 3: "c"]), at: Date())

        // One round with a different path is not enough: it may be a timeout
        // or a transient reroute.
        XCTAssertNil(detector.observe(path([1: "a", 2: "x", 3: "c"]), at: Date()))
        // Back to the old path, still no event.
        XCTAssertNil(detector.observe(path([1: "a", 2: "b", 3: "c"]), at: Date()))

        XCTAssertNil(detector.observe(path([1: "a", 2: "x", 3: "c"]), at: Date()))
        let change = detector.observe(path([1: "a", 2: "x", 3: "c"]), at: Date())
        XCTAssertEqual(change?.changes.count, 1)
        XCTAssertEqual(change?.changes.first?.hop, 2)
        XCTAssertEqual(change?.changes.first?.from, "b")
        XCTAssertEqual(change?.changes.first?.to, "x")
        XCTAssertEqual(change?.changes.first?.kind, .changed)

        // The new path is now the baseline.
        XCTAssertNil(detector.observe(path([1: "a", 2: "x", 3: "c"]), at: Date()))
    }

    func testEmptyPathIsIgnored() {
        var detector = RouteChangeDetector()
        _ = detector.observe(path([1: "a"]), at: Date())
        XCTAssertNil(detector.observe(RoutePath(hops: [:]), at: Date()))
        XCTAssertEqual(detector.confirmed, path([1: "a"]))
    }

    func testDiffReportsAddedRemovedAndChangedHops() {
        let changes = RouteChangeDetector.diff(
            from: path([1: "a", 2: "b", 3: "c"]),
            to: path([1: "a", 2: "b2", 4: "d"]))

        XCTAssertEqual(changes.map(\.hop), [2, 3, 4])
        XCTAssertEqual(changes[0].kind, .changed)
        XCTAssertEqual(changes[1].kind, .removed)
        XCTAssertEqual(changes[2].kind, .added)
        XCTAssertFalse(changes[2].summary.isEmpty)
    }

    // MARK: - Thresholds

    func testThresholdNotifiesOnceAndAgainOnlyAfterRecovery() {
        var tracker = RouteThresholdTracker()
        let settings = RouteMonitorSettings()

        let slow = stat(hop: 2, attempts: 4, replies: 4, average: 200)
        let first = tracker.evaluate(stats: [slow], settings: settings)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.kind, .latency)
        XCTAssertEqual(first.first?.hop, 2)

        XCTAssertTrue(tracker.evaluate(stats: [slow], settings: settings).isEmpty)

        let fast = stat(hop: 2, attempts: 4, replies: 4, average: 40)
        XCTAssertTrue(tracker.evaluate(stats: [fast], settings: settings).isEmpty)
        XCTAssertEqual(tracker.evaluate(stats: [slow], settings: settings).count, 1)
    }

    func testLossThresholdUsesWindowLoss() {
        var tracker = RouteThresholdTracker()
        let lossy = stat(hop: 3, attempts: 4, replies: 2, average: 30)

        let crossings = tracker.evaluate(stats: [lossy], settings: RouteMonitorSettings())
        XCTAssertEqual(crossings.count, 1)
        XCTAssertEqual(crossings.first?.kind, .loss)
        XCTAssertEqual(crossings.first?.value ?? 0, 50, accuracy: 0.001)
    }

    func testThresholdIgnoresHopsWithTooFewAttempts() {
        var tracker = RouteThresholdTracker()
        let crossing = tracker.evaluate(
            stats: [stat(hop: 1, attempts: 2, replies: 2, average: 900)],
            settings: RouteMonitorSettings())
        XCTAssertTrue(crossing.isEmpty)
    }

    // MARK: - Settings and cadence

    func testSettingsNormalizeClampThresholds() {
        var settings = RouteMonitorSettings()
        settings.latencyThresholdMilliseconds = 5
        settings.lossThresholdPercent = 250

        XCTAssertEqual(
            settings.normalized.latencyThresholdMilliseconds,
            RouteMonitorSettings.latencyRange.lowerBound)
        XCTAssertEqual(
            settings.normalized.lossThresholdPercent,
            RouteMonitorSettings.lossRange.upperBound)
    }

    func testCadenceSlowsWhenThePanelIsClosedAndInTheBackground() {
        XCTAssertEqual(
            RouteMonitorCadence.interval(isApplicationActive: true, isPanelVisible: true),
            RouteMonitorCadence.activeInterval)
        XCTAssertEqual(
            RouteMonitorCadence.interval(isApplicationActive: true, isPanelVisible: false),
            RouteMonitorCadence.panelClosedInterval)
        XCTAssertEqual(
            RouteMonitorCadence.interval(isApplicationActive: false, isPanelVisible: true),
            RouteMonitorCadence.backgroundInterval)
        XCTAssertEqual(
            RouteMonitorCadence.interval(isApplicationActive: false, isPanelVisible: false),
            RouteMonitorCadence.backgroundInterval)
    }

    // MARK: - Fixtures

    private func path(_ hops: [Int: String]) -> RoutePath {
        RoutePath(hops: hops)
    }

    private func stat(
        hop: Int, attempts: Int, replies: Int, average: Double?
    ) -> RouteHopStat {
        RouteHopStat(
            hop: hop, address: "10.0.0.\(hop)", attempts: attempts, replies: replies,
            averageMilliseconds: average, worstMilliseconds: average)
    }

    private func hop(_ ttl: Int, _ address: String?, _ milliseconds: Double?) -> MTRHop {
        MTRHop(
            hop: ttl,
            address: address,
            hostname: nil,
            sent: 1,
            received: address == nil ? 0 : 1,
            lastMilliseconds: milliseconds,
            bestMilliseconds: milliseconds,
            worstMilliseconds: milliseconds,
            averageMilliseconds: milliseconds,
            jitterMilliseconds: nil)
    }

    private func report(_ hops: [MTRHop]) -> MTRReport {
        MTRReport(host: "target", rounds: 1, startedAt: Date(), hops: hops)
    }
}
