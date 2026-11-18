import XCTest

final class ConnectionRulesTests: XCTestCase {
    private func connection(
        process: String = "Safari", pid: Int = 42, user: String = "demo",
        local: String = "10.0.0.2:52211", remote: String = "93.184.216.34:443",
        state: String = "ESTABLISHED"
    ) -> OpenConnection {
        OpenConnection(
            id: "\(pid)|\(local)|\(remote)|\(state)", process: process, pid: pid, user: user,
            protocolName: "IPv4", local: local, remote: remote, state: state)
    }

    func testPortMatchesEitherEndpoint() {
        let rule = ConnectionBlockRule(scope: .port, value: "443")
        XCTAssertTrue(rule.matches(connection()))
        XCTAssertTrue(rule.matches(connection(local: "10.0.0.2:443", remote: "1.1.1.1:80")))
        XCTAssertFalse(rule.matches(connection(remote: "93.184.216.34:80")))
    }

    func testRemoteHostAndProcessMatchCaseInsensitively() {
        XCTAssertTrue(
            ConnectionBlockRule(scope: .remoteHost, value: "93.184.216.34")
                .matches(connection()))
        XCTAssertFalse(
            ConnectionBlockRule(scope: .remoteHost, value: "example.com")
                .matches(connection()))
        XCTAssertTrue(
            ConnectionBlockRule(scope: .process, value: "safari").matches(connection()))
        XCTAssertTrue(ConnectionBlockRule(scope: .pid, value: "42").matches(connection()))
        XCTAssertFalse(ConnectionBlockRule(scope: .user, value: "root").matches(connection()))
    }

    func testTrafficMatchingIgnoresEndpointScopes() {
        let rows = [
            ProcessTrafficDelta(
                process: "Safari", pid: 42, receivedBytes: 10, sentBytes: 4,
                receivedBytesPerSecond: 1, sentBytesPerSecond: 0.4)
        ]
        XCTAssertTrue(
            ConnectionBlockRuleMatcher.matches(
                process: rows[0].process, pid: rows[0].pid,
                rules: [ConnectionBlockRule(scope: .process, value: "Safari")]))
        XCTAssertFalse(
            ConnectionBlockRuleMatcher.matches(
                process: rows[0].process, pid: rows[0].pid,
                rules: [ConnectionBlockRule(scope: .port, value: "443")]))
    }

    func testSocketGroupingCollapsesSharedLocalEndpoint() {
        let rows = [
            connection(local: "10.0.0.2:52211", remote: "1.1.1.1:443"),
            connection(pid: 43, local: "10.0.0.2:52211", remote: "8.8.8.8:443"),
            connection(process: "Mail", pid: 44, local: "10.0.0.2:53000", remote: "2.2.2.2:993"),
        ]
        let groups = ConnectionGrouping.bySocket(rows)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.connections.count, 2)
        XCTAssertEqual(groups.first?.processes.count, 1)
    }

    func testTrafficGroupingByApplicationAggregatesPIDs() {
        let rows = [
            ProcessTrafficDelta(
                process: "Safari", pid: 1, receivedBytes: 10, sentBytes: 2,
                receivedBytesPerSecond: 10, sentBytesPerSecond: 2),
            ProcessTrafficDelta(
                process: "Safari Helper", pid: 2, receivedBytes: 5, sentBytes: 1,
                receivedBytesPerSecond: 5, sentBytesPerSecond: 1),
        ]
        let groups = TrafficGrouping.byApplication(rows) { _ in "Safari" }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].receivedBytesPerSecond, 15)
        let byProcess = TrafficGrouping.byProcess(rows)
        XCTAssertEqual(byProcess.count, 2)
    }
}
