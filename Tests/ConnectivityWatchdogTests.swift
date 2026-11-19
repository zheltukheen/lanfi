import LanFiCore
import XCTest

final class ConnectivityWatchdogTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private var healthyPayload: ConnectivityProbeOutcome {
        ConnectivityProbeOutcome(
            statusCode: 200,
            redirected: false,
            body: "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>",
            latencyMilliseconds: 42)
    }

    private var portalPayload: ConnectivityProbeOutcome {
        ConnectivityProbeOutcome(
            statusCode: 200,
            redirected: false,
            body: "<html><body>Sign in to Wi-Fi</body></html>",
            latencyMilliseconds: 18)
    }

    func testSuccessMakesOnline() {
        var machine = ConnectivityWatchdogMachine()
        let change = machine.record(pathReachable: true, probe: healthyPayload, at: start)

        XCTAssertEqual(change?.from, .unknown)
        XCTAssertEqual(change?.to, .online)
        XCTAssertEqual(machine.verdict, .online)
        XCTAssertEqual(machine.latencyMilliseconds, 42)
        XCTAssertEqual(machine.lastCheckedAt, start)
    }

    func testSingleFailedProbeKeepsTheWorkingVerdict() {
        var machine = ConnectivityWatchdogMachine()
        machine.record(pathReachable: true, probe: healthyPayload, at: start)

        XCTAssertNil(
            machine.record(
                pathReachable: true, probe: nil, at: start.addingTimeInterval(30)))
        XCTAssertEqual(machine.verdict, .online)
        XCTAssertEqual(machine.consecutiveFailures, 1)

        let change = machine.record(
            pathReachable: true, probe: .failure, at: start.addingTimeInterval(60))
        XCTAssertEqual(change?.to, .offline)
        XCTAssertEqual(machine.verdict, .offline)
    }

    func testFirstCheckFailureStaysUnknown() {
        var machine = ConnectivityWatchdogMachine()
        XCTAssertNil(machine.record(pathReachable: true, probe: .failure, at: start))
        XCTAssertEqual(machine.verdict, .unknown)
    }

    func testLinkLossIsImmediate() {
        var machine = ConnectivityWatchdogMachine()
        machine.record(pathReachable: true, probe: healthyPayload, at: start)

        let change = machine.record(
            pathReachable: false, probe: nil, at: start.addingTimeInterval(15))
        XCTAssertEqual(change?.to, .offline)
        XCTAssertEqual(machine.verdict, .offline)
    }

    func testPortalPageIsCaptivePortal() {
        var machine = ConnectivityWatchdogMachine()
        let change = machine.record(pathReachable: true, probe: portalPayload, at: start)

        XCTAssertEqual(change?.to, .captivePortal)
        XCTAssertFalse(machine.verdict.isOnline)
    }

    func testRedirectIsCaptivePortal() {
        let redirected = ConnectivityProbeOutcome(
            statusCode: 200, redirected: true, body: "Success", latencyMilliseconds: 12)
        XCTAssertEqual(ConnectivityProbeClassifier.classify(redirected), .captivePortal)
    }

    func testNonSuccessStatusIsOffline() {
        let missing = ConnectivityProbeOutcome(
            statusCode: 404, redirected: false, body: "Not Found", latencyMilliseconds: 9)
        XCTAssertEqual(ConnectivityProbeClassifier.classify(missing), .offline)
    }

    func testLatencySurvivesAnOutage() {
        var machine = ConnectivityWatchdogMachine()
        machine.record(pathReachable: true, probe: healthyPayload, at: start)
        machine.record(pathReachable: false, probe: nil, at: start.addingTimeInterval(30))

        XCTAssertEqual(machine.verdict, .offline)
        XCTAssertEqual(machine.latencyMilliseconds, 42)
    }

    func testRecoveryFromCaptivePortal() {
        var machine = ConnectivityWatchdogMachine()
        machine.record(pathReachable: true, probe: portalPayload, at: start)
        let change = machine.record(
            pathReachable: true, probe: healthyPayload, at: start.addingTimeInterval(30))

        XCTAssertEqual(change?.from, .captivePortal)
        XCTAssertEqual(change?.to, .online)
    }

    func testPolicyHonoursToggles() {
        var settings = AppSettings.ConnectivitySettings()
        settings.notifyOffline = false
        var policy = ConnectivityAlertPolicy()
        let change = ConnectivityWatchdogMachine.Change(from: .online, to: .offline)

        XCTAssertFalse(
            policy.shouldNotify(
                change: change, settings: settings, quietHours: MonitorAlertSettings(), now: start))

        settings.notifyOffline = true
        XCTAssertTrue(
            policy.shouldNotify(
                change: change, settings: settings, quietHours: MonitorAlertSettings(), now: start))
    }

    func testFirstOnlineIsNotARecovery() {
        var policy = ConnectivityAlertPolicy()
        let change = ConnectivityWatchdogMachine.Change(from: .unknown, to: .online)

        XCTAssertFalse(
            policy.shouldNotify(
                change: change, settings: AppSettings.ConnectivitySettings(),
                quietHours: MonitorAlertSettings(), now: start))
    }

    func testQuietHoursSuppressNotifications() {
        var quiet = MonitorAlertSettings()
        quiet.quietHoursEnabled = true
        quiet.quietStartHour = 22
        quiet.quietEndHour = 7

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let night = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 19, hour: 23))!

        var policy = ConnectivityAlertPolicy()
        let change = ConnectivityWatchdogMachine.Change(from: .online, to: .offline)
        XCTAssertFalse(
            policy.shouldNotify(
                change: change, settings: AppSettings.ConnectivitySettings(),
                quietHours: quiet, now: night, calendar: calendar))
    }

    func testCooldownSuppressesRepeats() {
        var settings = AppSettings.ConnectivitySettings()
        settings.cooldownMinutes = 5
        var policy = ConnectivityAlertPolicy()
        let change = ConnectivityWatchdogMachine.Change(from: .online, to: .offline)
        let quiet = MonitorAlertSettings()

        XCTAssertTrue(
            policy.shouldNotify(
                change: change, settings: settings, quietHours: quiet, now: start))
        XCTAssertFalse(
            policy.shouldNotify(
                change: change, settings: settings, quietHours: quiet,
                now: start.addingTimeInterval(60)))
        XCTAssertTrue(
            policy.shouldNotify(
                change: change, settings: settings, quietHours: quiet,
                now: start.addingTimeInterval(301)))
    }

    func testDefaultsAndNormalization() {
        var settings = AppSettings()
        XCTAssertTrue(settings.connectivity.enabled)
        XCTAssertEqual(settings.connectivity.intervalSeconds, 30)
        XCTAssertFalse(settings.connectivity.primaryProbeURL.isEmpty)

        settings.connectivity.intervalSeconds = 1000
        settings.connectivity.primaryProbeURL = ""
        settings.normalize()

        XCTAssertEqual(settings.connectivity.intervalSeconds, 30)
        XCTAssertEqual(
            settings.connectivity.primaryProbeURL,
            AppSettings.ConnectivitySettings().primaryProbeURL)
    }
}
