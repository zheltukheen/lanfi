import XCTest

final class TrafficAccountingTests: XCTestCase {
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

    func testRecordsPerDayInterfaceAndTotal() {
        var ledger = TrafficLedger.empty
        ledger.record(
            received: 1_000, sent: 400, interface: "en0", at: date("2026-11-19 10:00"),
            calendar: calendar)
        ledger.record(
            received: 500, sent: 100, interface: "en0", at: date("2026-11-19 12:00"),
            calendar: calendar)
        ledger.record(
            received: 300, sent: 0, interface: "en5", at: date("2026-11-18 09:00"),
            calendar: calendar)

        XCTAssertEqual(ledger.total, TrafficVolume(received: 1_800, sent: 500))
        XCTAssertEqual(
            ledger.perDay["2026-11-19"], TrafficVolume(received: 1_500, sent: 500))
        XCTAssertEqual(ledger.perInterface["en5"], TrafficVolume(received: 300, sent: 0))
    }

    func testEmptyDeltasAreIgnored() {
        var ledger = TrafficLedger.empty
        ledger.record(received: 0, sent: 0, interface: "en0", at: Date(), calendar: calendar)
        XCTAssertTrue(ledger.perDay.isEmpty)
        XCTAssertNil(ledger.updatedAt)
    }

    func testTodayAndWeekAndMonthRanges() {
        var ledger = TrafficLedger.empty
        let now = date("2026-11-19 23:00")
        ledger.record(received: 100, sent: 0, interface: "en0", at: now, calendar: calendar)
        ledger.record(
            received: 200, sent: 0, interface: "en0", at: date("2026-11-16 08:00"),
            calendar: calendar)
        ledger.record(
            received: 400, sent: 0, interface: "en0", at: date("2026-11-02 08:00"),
            calendar: calendar)
        ledger.record(
            received: 800, sent: 0, interface: "en0", at: date("2026-10-31 08:00"),
            calendar: calendar)

        XCTAssertEqual(ledger.volume(for: .today, now: now, calendar: calendar).total, 100)
        XCTAssertEqual(ledger.volume(for: .week, now: now, calendar: calendar).total, 300)
        XCTAssertEqual(ledger.volume(for: .month, now: now, calendar: calendar).total, 700)
        XCTAssertEqual(ledger.volume(for: .all, now: now, calendar: calendar).total, 1_500)
    }

    func testDayBoundaryFollowsTheCalendar() {
        var ledger = TrafficLedger.empty
        ledger.record(
            received: 10, sent: 0, interface: "en0", at: date("2026-11-18 23:59"),
            calendar: calendar)
        ledger.record(
            received: 20, sent: 0, interface: "en0", at: date("2026-11-19 00:01"),
            calendar: calendar)
        XCTAssertEqual(ledger.perDay.count, 2)
        XCTAssertEqual(
            ledger.volume(for: .today, now: date("2026-11-19 12:00"), calendar: calendar).total,
            20)
    }

    func testPruneKeepsRecentDays() {
        var ledger = TrafficLedger.empty
        ledger.record(
            received: 10, sent: 0, interface: "en0", at: date("2025-01-01 10:00"),
            calendar: calendar)
        ledger.record(
            received: 20, sent: 0, interface: "en0", at: date("2026-11-19 10:00"),
            calendar: calendar)
        ledger.prune(now: date("2026-11-19 12:00"), keepDays: 30, calendar: calendar)
        XCTAssertEqual(ledger.perDay.keys.sorted(), ["2026-11-19"])
        // The lifetime total never loses history.
        XCTAssertEqual(ledger.total.total, 30)
    }

    func testCSVHasOneRowPerDay() {
        var ledger = TrafficLedger.empty
        ledger.record(
            received: 10, sent: 5, interface: "en0", at: date("2026-11-19 10:00"),
            calendar: calendar)
        ledger.record(
            received: 7, sent: 3, interface: "en0", at: date("2026-11-18 10:00"),
            calendar: calendar)
        let lines = ledger.csv(calendar: calendar).split(separator: "\n")
        XCTAssertEqual(lines.first, "date,received_bytes,sent_bytes")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], "2026-11-18,7,3")
        XCTAssertEqual(lines[2], "2026-11-19,10,5")
    }

    func testRoundTripsThroughCodable() throws {
        var ledger = TrafficLedger.empty
        ledger.record(
            received: 1, sent: 2, interface: "en0", at: date("2026-11-19 10:00"),
            calendar: calendar)
        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(TrafficLedger.self, from: data)
        XCTAssertEqual(decoded, ledger)
    }

    func testByteFormatting() {
        XCTAssertEqual(TrafficByteFormat.string(0), "0 B")
        XCTAssertEqual(TrafficByteFormat.string(999), "999 B")
        XCTAssertEqual(TrafficByteFormat.string(1_500), "1.50 kB")
        XCTAssertEqual(TrafficByteFormat.string(2_500_000_000), "2.50 GB")
    }

    func testRangesHaveTitles() {
        XCTAssertEqual(TrafficRange.allCases.count, 4)
        XCTAssertFalse(TrafficRange.today.title.isEmpty)
    }
}
