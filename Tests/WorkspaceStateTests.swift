import XCTest

final class WorkspaceStateTests: XCTestCase {
    // MARK: - History chart mode

    func testHistoryChartModeFlags() {
        XCTAssertTrue(HistoryChartMode.signal.showsSignal)
        XCTAssertFalse(HistoryChartMode.signal.showsNoise)
        XCTAssertFalse(HistoryChartMode.noise.showsSignal)
        XCTAssertTrue(HistoryChartMode.noise.showsNoise)
        XCTAssertTrue(HistoryChartMode.both.showsSignal)
        XCTAssertTrue(HistoryChartMode.both.showsNoise)
        XCTAssertEqual(
            HistoryChartMode.allCases.compactMap { HistoryChartMode(rawValue: $0.rawValue) }.count,
            3)
    }

    // MARK: - Visibility advice

    func testSixGHzPreferredScanningChannel() {
        let psc = makeNetwork(band: .band6, channel: 37)
        let advice = VisibilityAdvisor.advice(for: psc)
        XCTAssertEqual(advice.map(\.kind), [.preferredScanning])

        let nonPSC = makeNetwork(band: .band6, channel: 33)
        let hint = VisibilityAdvisor.advice(for: nonPSC)
        XCTAssertEqual(hint.map(\.kind), [.notPreferredScanning])
        XCTAssertTrue(hint.first?.detail.lowercased().contains("passive") ?? false)
    }

    func testDFSAndHiddenSSIDAdvice() {
        let dfs = makeNetwork(band: .band5, channel: 52)
        XCTAssertEqual(VisibilityAdvisor.advice(for: dfs).map(\.kind), [.dfs])

        let hidden = makeNetwork(ssid: "")
        XCTAssertEqual(VisibilityAdvisor.advice(for: hidden).map(\.kind), [.hiddenSSID])

        let plain = makeNetwork(band: .band5, channel: 36)
        XCTAssertTrue(VisibilityAdvisor.advice(for: plain).isEmpty)
        XCTAssertFalse(VisibilityAdvisor.emptyScanHint.isEmpty)
    }

    // MARK: - Workspace placeholder

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testFilteredOutranksOtherStates() {
        let placeholder = WorkspacePlaceholderEvaluator.evaluate(
            scanHealth: .healthy, visibleCount: 0, totalCount: 5, hasActiveFilters: true,
            lastScan: now, isSessionLoaded: false, scanInterval: 3, now: now)
        XCTAssertEqual(placeholder, .filtered)
    }

    func testPermissionAndHardwareStates() {
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .permissionDenied, visibleCount: 0, totalCount: 0,
                hasActiveFilters: false, lastScan: nil, isSessionLoaded: false, scanInterval: 3,
                now: now),
            .noPermission)
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .noWiFiHardware, visibleCount: 0, totalCount: 0,
                hasActiveFilters: false, lastScan: nil, isSessionLoaded: false, scanInterval: 3,
                now: now),
            .noWiFiHardware)
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .scanFailed("Wi-Fi is off"), visibleCount: 0, totalCount: 0,
                hasActiveFilters: false, lastScan: nil, isSessionLoaded: false, scanInterval: 3,
                now: now),
            .scanFailed("Wi-Fi is off"))
    }

    func testNoScanBeforeTheFirstResult() {
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .noNetworks, visibleCount: 0, totalCount: 0, hasActiveFilters: false,
                lastScan: nil, isSessionLoaded: false, scanInterval: 3, now: now),
            .noScan)
    }

    func testStaleDataAfterTheThreshold() {
        let staleScan = now.addingTimeInterval(-120)
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .healthy, visibleCount: 4, totalCount: 4, hasActiveFilters: false,
                lastScan: staleScan, isSessionLoaded: false, scanInterval: 3, now: now),
            .staleData(staleScan))
    }

    func testFreshScanAndLoadedSessionAreHealthy() {
        let recent = now.addingTimeInterval(-2)
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .healthy, visibleCount: 4, totalCount: 4, hasActiveFilters: false,
                lastScan: recent, isSessionLoaded: false, scanInterval: 3, now: now),
            .none)
        // A loaded session pauses scanning on purpose, so old data is not stale.
        XCTAssertEqual(
            WorkspacePlaceholderEvaluator.evaluate(
                scanHealth: .healthy, visibleCount: 4, totalCount: 4, hasActiveFilters: false,
                lastScan: now.addingTimeInterval(-3600), isSessionLoaded: true, scanInterval: 3,
                now: now),
            .none)
    }

    func testStaleThresholdFollowsTheScanInterval() {
        XCTAssertEqual(WorkspacePlaceholderEvaluator.staleAfter(3), 45)
        XCTAssertEqual(WorkspacePlaceholderEvaluator.staleAfter(30), 300)
    }
}
