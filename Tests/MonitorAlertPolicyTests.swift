import XCTest

final class MonitorAlertPolicyTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute))!
    }

    private func event(_ kind: MonitorEventKind, at date: Date) -> MonitorEvent {
        MonitorEvent(
            at: date, kind: kind, bssid: "AA:BB:CC:DD:EE:01", ssid: "Office",
            detail: "test")
    }

    func testDisabledKindIsIgnored() {
        var settings = MonitorAlertSettings()
        settings.weakSignal = false
        var policy = MonitorAlertPolicy()
        let event = event(.weakSignal, at: date(hour: 12))

        XCTAssertFalse(
            policy.shouldNotify(event: event, settings: settings, now: event.at, calendar: calendar))
    }

    func testEnabledKindNotifies() {
        var settings = MonitorAlertSettings()
        settings.securityChange = true
        var policy = MonitorAlertPolicy()
        let event = event(.securityChanged, at: date(hour: 12))

        XCTAssertTrue(
            policy.shouldNotify(event: event, settings: settings, now: event.at, calendar: calendar))
    }

    func testOvernightQuietHours() {
        var settings = MonitorAlertSettings()
        settings.quietHoursEnabled = true
        settings.quietStartHour = 22
        settings.quietEndHour = 7

        XCTAssertTrue(settings.isQuiet(at: date(hour: 23), calendar: calendar))
        XCTAssertTrue(settings.isQuiet(at: date(hour: 6), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: date(hour: 12), calendar: calendar))
    }

    func testDaytimeQuietHours() {
        var settings = MonitorAlertSettings()
        settings.quietHoursEnabled = true
        settings.quietStartHour = 9
        settings.quietEndHour = 18

        XCTAssertTrue(settings.isQuiet(at: date(hour: 9), calendar: calendar))
        XCTAssertTrue(settings.isQuiet(at: date(hour: 17), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: date(hour: 18), calendar: calendar))
        XCTAssertFalse(settings.isQuiet(at: date(hour: 8), calendar: calendar))
    }

    func testQuietHoursSuppressNotifications() {
        var settings = MonitorAlertSettings()
        settings.quietHoursEnabled = true
        settings.quietStartHour = 22
        settings.quietEndHour = 7
        var policy = MonitorAlertPolicy()
        let event = event(.weakSignal, at: date(hour: 23))

        XCTAssertFalse(
            policy.shouldNotify(event: event, settings: settings, now: event.at, calendar: calendar))
    }

    func testCooldownSuppressesRepeatedEvents() {
        var settings = MonitorAlertSettings()
        settings.cooldownMinutes = 5
        var policy = MonitorAlertPolicy()
        let first = event(.securityChanged, at: date(hour: 12))

        XCTAssertTrue(
            policy.shouldNotify(event: first, settings: settings, now: first.at, calendar: calendar))

        let second = event(.securityChanged, at: first.at.addingTimeInterval(60))
        XCTAssertFalse(
            policy.shouldNotify(event: second, settings: settings, now: second.at, calendar: calendar))

        let third = event(.securityChanged, at: first.at.addingTimeInterval(301))
        XCTAssertTrue(
            policy.shouldNotify(event: third, settings: settings, now: third.at, calendar: calendar))
    }
}
