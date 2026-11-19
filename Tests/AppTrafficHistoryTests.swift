import XCTest

final class AppTrafficHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    private func delta(_ process: String, pid: Int, received: UInt64, sent: UInt64)
        -> ProcessTrafficDelta
    {
        ProcessTrafficDelta(
            process: process, pid: pid, receivedBytes: received, sentBytes: sent,
            receivedBytesPerSecond: 0, sentBytesPerSecond: 0)
    }

    func testRecordsHourlyBucketsPerApp() {
        var history = AppTrafficHistory.empty
        history.record(
            [delta("Safari", pid: 10, received: 100, sent: 20)],
            at: date("2026-11-19 10:05"), calendar: calendar)
        history.record(
            [delta("Safari", pid: 11, received: 50, sent: 5)],
            at: date("2026-11-19 10:55"), calendar: calendar)
        history.record(
            [delta("Safari", pid: 10, received: 7, sent: 1)],
            at: date("2026-11-19 11:05"), calendar: calendar)

        XCTAssertEqual(
            history.apps["Safari"]?["2026-11-19T10"], TrafficVolume(received: 150, sent: 25))
        XCTAssertEqual(
            history.volume(forApp: "Safari", on: date("2026-11-19 12:00"), calendar: calendar),
            TrafficVolume(received: 157, sent: 26))
    }

    func testExcludesLanFiAndEmptyDeltas() {
        var history = AppTrafficHistory.empty
        history.record(
            [
                delta("LanFi", pid: 99, received: 1_000, sent: 1_000),
                delta("Safari", pid: 10, received: 0, sent: 0),
            ],
            at: date("2026-11-19 10:05"), excludingPIDs: [99], calendar: calendar)
        XCTAssertTrue(history.apps.isEmpty)
        XCTAssertNil(history.updatedAt)
    }

    func testTopAppsOrderByTotalAndHideOtherDays() {
        var history = AppTrafficHistory.empty
        history.record(
            [
                delta("Safari", pid: 10, received: 100, sent: 0),
                delta("Mail", pid: 11, received: 300, sent: 0),
                delta("Slack", pid: 12, received: 0, sent: 50),
            ],
            at: date("2026-11-19 09:00"), calendar: calendar)
        history.record(
            [delta("Mail", pid: 11, received: 9_000, sent: 0)],
            at: date("2026-11-18 09:00"), calendar: calendar)

        let top = history.topApps(on: date("2026-11-19 20:00"), calendar: calendar)
        XCTAssertEqual(top.map(\.app), ["Mail", "Safari", "Slack"])
        XCTAssertEqual(top.first?.volume.total, 300)
        XCTAssertEqual(
            history.dayTotal(on: date("2026-11-19 20:00"), calendar: calendar).total, 450)
    }

    func testPruneDropsOldDaysAndEmptyApps() {
        var history = AppTrafficHistory.empty
        history.record(
            [delta("Safari", pid: 10, received: 5, sent: 0)],
            at: date("2026-10-01 10:00"), calendar: calendar)
        history.record(
            [delta("Mail", pid: 11, received: 7, sent: 0)],
            at: date("2026-11-19 10:00"), calendar: calendar)
        history.prune(now: date("2026-11-19 12:00"), keepDays: 7, calendar: calendar)

        XCTAssertNil(history.apps["Safari"])
        XCTAssertEqual(history.apps["Mail"]?.count, 1)
    }

    func testHourKeyAndCsv() {
        XCTAssertEqual(
            AppTrafficHistory.hourKey(date("2026-11-19 07:30"), calendar: calendar),
            "2026-11-19T07")

        var history = AppTrafficHistory.empty
        history.record(
            [delta("Safari", pid: 10, received: 10, sent: 2)],
            at: date("2026-11-19 10:00"), calendar: calendar)
        let lines = history.csv(on: date("2026-11-19 20:00"), calendar: calendar)
            .split(separator: "\n")
        XCTAssertEqual(lines.first, "date,app,received_bytes,sent_bytes")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "2026-11-19,\"Safari\",10,2")
    }

    func testRoundTripsThroughCodable() throws {
        var history = AppTrafficHistory.empty
        history.record(
            [delta("Safari", pid: 10, received: 3, sent: 4)],
            at: date("2026-11-19 10:00"), calendar: calendar)
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(AppTrafficHistory.self, from: data), history)
    }
}
