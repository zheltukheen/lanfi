import XCTest

final class ListenerWatchTests: XCTestCase {
    private let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        python3   12345 user    3u  IPv4 0x1111111111111111      0t0  TCP *:8000 (LISTEN)
        postgres    900 user    6u  IPv4 0x2222222222222222      0t0  TCP 127.0.0.1:5432 (LISTEN)
        identitys   675 user    7u  IPv4 0x3333333333333333      0t0  UDP *:*
        node       2345 user    9u  IPv4 0x4444444444444444      0t0  TCP 192.168.1.10:3000 (LISTEN)
        Safari     9999 user    7u  IPv4 0x5555555555555555      0t0  TCP 192.168.1.10:52344->142.250.185.78:443 (ESTABLISHED)
        """

    private var listeners: [ListenerSummary] {
        OpenConnectionsParser.parse(output).compactMap(ListenerSummary.init(connection:))
    }

    private func listener(
        id: String, process: String = "python3", local: String = "*:8000"
    ) -> ListenerSummary {
        ListenerSummary(
            id: id, process: process, pid: 42, user: "user", transport: "TCP", local: local,
            exposure: .allInterfaces)
    }

    func testParsesUDPAndTransport() {
        let connections = OpenConnectionsParser.parse(output)
        let udp = connections.first { $0.process == "identitys" }

        XCTAssertEqual(udp?.transport, "UDP")
        XCTAssertTrue(udp?.isUDP == true)
        XCTAssertTrue(udp?.isListener == true)
        XCTAssertEqual(udp?.state, "—")
        XCTAssertEqual(udp?.remote, "—")
    }

    func testOnlyListenersBecomeSummaries() {
        XCTAssertEqual(listeners.count, 4)
        XCTAssertFalse(listeners.contains { $0.process == "Safari" })
    }

    func testExposureClassification() {
        XCTAssertEqual(SocketExposureClassifier.classify(local: "*:8000"), .allInterfaces)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "0.0.0.0:9000"), .allInterfaces)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "[::]:9000"), .allInterfaces)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "127.0.0.1:5432"), .loopback)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "[::1]:80"), .loopback)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "localhost:3000"), .loopback)
        XCTAssertEqual(
            SocketExposureClassifier.classify(local: "192.168.1.10:3000"), .specificAddress)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "[fe80::1]:22"), .specificAddress)
        XCTAssertEqual(SocketExposureClassifier.classify(local: "nonsense"), .unknown)
    }

    func testSummariesCarryExposure() {
        let byProcess = Dictionary(uniqueKeysWithValues: listeners.map { ($0.process, $0) })
        XCTAssertEqual(byProcess["python3"]?.exposure, .allInterfaces)
        XCTAssertEqual(byProcess["postgres"]?.exposure, .loopback)
        XCTAssertEqual(byProcess["node"]?.exposure, .specificAddress)

        XCTAssertEqual(
            listeners.filter { $0.exposure.isLANReachable }.map(\.process).sorted(),
            ["identitys", "node", "python3"])
    }

    func testDiffReportsOpenedAndClosedListeners() {
        let first = listener(id: "1")
        let added = listener(id: "2", process: "httpd", local: "*:80")
        let at = Date(timeIntervalSince1970: 1_780_000_000)

        let opened = ListenerWatchDiff.changes(previous: [first], current: [first, added], at: at)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.kind, .opened)
        XCTAssertEqual(opened.first?.listener.process, "httpd")

        let closed = ListenerWatchDiff.changes(previous: [first, added], current: [first], at: at)
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed.first?.kind, .closed)
        XCTAssertEqual(closed.first?.listener.id, "2")
    }

    func testDiffIsEmptyForIdenticalSamples() {
        let rows = [listener(id: "1"), listener(id: "2", local: "127.0.0.1:5432")]
        XCTAssertTrue(
            ListenerWatchDiff.changes(
                previous: rows, current: rows, at: Date(timeIntervalSince1970: 0)
            ).isEmpty)
    }

    func testTCPAndUDPOnTheSameEndpointAreDistinct() {
        let tcp = OpenConnection(
            id: "1|TCP|*:8000|—|LISTEN", process: "python3", pid: 1, user: "user",
            protocolName: "IPv4", transport: "TCP", local: "*:8000", remote: "—", state: "LISTEN")
        let udp = OpenConnection(
            id: "1|UDP|*:8000|—|—", process: "python3", pid: 1, user: "user", protocolName: "IPv4",
            transport: "UDP", local: "*:8000", remote: "—", state: "—")

        XCTAssertNotEqual(
            ListenerSummary(connection: tcp)?.id, ListenerSummary(connection: udp)?.id)
    }

    func testNotificationCopyNamesTheEndpoint() {
        let change = ListenerChange(
            id: "1", kind: .opened, listener: listener(id: "1"), at: Date())
        XCTAssertTrue(change.notificationBody.contains("*:8000"))
        XCTAssertTrue(change.notificationTitle.contains("LanFi"))
    }
}
