import XCTest

@MainActor
final class UptimeTests: XCTestCase {

    func testTargetNormalisation() throws {
        let http = try XCTUnwrap(
            UptimeTarget.make(
                name: "API", address: "example.com", kind: .http, intervalMinutes: 5))
        XCTAssertTrue(http.address.hasPrefix("https://example.com"))
        XCTAssertEqual(http.name, "API")

        let tcp = try XCTUnwrap(
            UptimeTarget.make(
                name: "", address: "example.com:443", kind: .tcp, intervalMinutes: 5))
        XCTAssertEqual(tcp.address, "example.com:443")
        XCTAssertEqual(tcp.name, "example.com:443")

        let tls = try XCTUnwrap(
            UptimeTarget.make(
                name: "TLS", address: "example.com", kind: .tls, intervalMinutes: 5))
        XCTAssertEqual(tls.address, "example.com:443")
        XCTAssertEqual(tls.tlsTarget?.port, 443)

        let dns = try XCTUnwrap(
            UptimeTarget.make(
                name: "DNS", address: "example.com", kind: .dns, intervalMinutes: 5))
        XCTAssertEqual(dns.address, "example.com")

        let mail = try XCTUnwrap(
            UptimeTarget.make(
                name: "Mail", address: "example.com", kind: .mail, intervalMinutes: 5))
        XCTAssertEqual(mail.address, "example.com")
        XCTAssertEqual(mail.mailDomain, "example.com")

        XCTAssertNil(
            UptimeTarget.make(name: "x", address: "example.com", kind: .tcp, intervalMinutes: 5))
        XCTAssertNil(
            UptimeTarget.make(name: "x", address: "   ", kind: .http, intervalMinutes: 5))
    }

    func testTransitionEvents() {
        XCTAssertEqual(UptimeTransition.event(previousUp: nil, currentUp: false), .down)
        XCTAssertNil(UptimeTransition.event(previousUp: nil, currentUp: true))
        XCTAssertEqual(UptimeTransition.event(previousUp: true, currentUp: false), .down)
        XCTAssertEqual(UptimeTransition.event(previousUp: false, currentUp: true), .recovered)
        XCTAssertNil(UptimeTransition.event(previousUp: true, currentUp: true))
        XCTAssertNil(UptimeTransition.event(previousUp: false, currentUp: false))
    }

    func testStoreRoundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UptimeStore(directory: directory)
        let target = UptimeTarget.make(
            name: "API", address: "https://example.com", kind: .http, intervalMinutes: 5)!
        let check = UptimeCheck(
            targetID: target.id, isUp: true, latencyMilliseconds: 12, detail: "HTTP 200")
        store.save(UptimeStoreSnapshot(targets: [target], checks: [check]))

        let loaded = store.load()
        XCTAssertEqual(loaded.targets.map(\.id), [target.id])
        XCTAssertEqual(loaded.targets.first?.address, target.address)
        XCTAssertEqual(loaded.checks.first?.isUp, true)
        XCTAssertEqual(loaded.checks.first?.latencyMilliseconds, 12)
    }

    func testDownAndRecoveryProduceNotifications() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UptimeStore(directory: directory)
        let checker = ScriptedUptimeChecker(results: [false, true])
        let notifier = RecordingUserNotifier()
        let monitor = UptimeMonitor(
            store: store, checker: checker, notifier: notifier, startAutomatically: false)
        let target = UptimeTarget.make(
            name: "API", address: "https://example.com", kind: .http, intervalMinutes: 5)!
        monitor.add(target, checkImmediately: false)

        await monitor.checkNow(target.id)
        XCTAssertEqual(monitor.state(for: target).isUp, false)
        XCTAssertEqual(monitor.downCount, 1)

        await monitor.checkNow(target.id)
        XCTAssertEqual(monitor.state(for: target).isUp, true)
        XCTAssertEqual(monitor.downCount, 0)
        XCTAssertEqual(monitor.state(for: target).outageCount, 1)
        XCTAssertEqual(monitor.state(for: target).uptimePercent ?? 0, 50, accuracy: 0.001)

        let events = await notifier.events
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], "API is down")
        XCTAssertEqual(events[1], "API is back up")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-uptime-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor ScriptedUptimeChecker: UptimeChecking {
    private var results: [Bool]

    init(results: [Bool]) {
        self.results = results
    }

    func check(_ target: UptimeTarget) async -> UptimeCheck {
        let up = results.isEmpty ? true : results.removeFirst()
        return UptimeCheck(
            targetID: target.id,
            isUp: up,
            latencyMilliseconds: up ? 10 : nil,
            detail: up ? "HTTP 200" : "Connection refused"
        )
    }
}

private actor RecordingUserNotifier: UserNotifying {
    private(set) var events: [String] = []

    func notify(title: String, body: String) async {
        events.append(title)
    }
}
