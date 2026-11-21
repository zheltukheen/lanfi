import XCTest

final class ConnectionRulesTests: XCTestCase {
    private func connection(
        process: String = "Safari", pid: Int = 42, user: String = "demo",
        local: String = "10.0.0.2:52211", remote: String = "93.184.216.34:443",
        state: String = "ESTABLISHED"
    ) -> OpenConnection {
        OpenConnection(
            id: "\(pid)|TCP|\(local)|\(remote)|\(state)", process: process, pid: pid, user: user,
            protocolName: "IPv4", transport: "TCP", local: local, remote: remote, state: state)
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

    func testDisabledRuleStopsMatching() {
        var rule = ConnectionBlockRule(scope: .port, value: "443", isEnabled: false)
        XCTAssertFalse(ConnectionBlockRuleMatcher.matches(connection(), rules: [rule]))
        rule.isEnabled = true
        XCTAssertTrue(ConnectionBlockRuleMatcher.matches(connection(), rules: [rule]))
    }

    func testModelUpdatesTogglesAndRoundTripsRulesThroughJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = ConnectionRulesModel(
            store: ConnectionBlockRuleStore(directory: root.appendingPathComponent("a")))

        var rule = ConnectionBlockRule(scope: .application, value: "Mail")
        model.add(rule)
        rule.scope = .process
        rule.value = "MailHelper"
        model.update(rule)
        XCTAssertEqual(model.rules.count, 1)
        XCTAssertEqual(model.rules.first?.value, "MailHelper")

        model.setEnabled(false, id: rule.id)
        XCTAssertEqual(model.rules.first?.isEnabled, false)

        let data = try model.exportData()
        let other = ConnectionRulesModel(
            store: ConnectionBlockRuleStore(directory: root.appendingPathComponent("b")))
        let first = try other.importData(data)
        XCTAssertEqual(first.added, 1)
        XCTAssertEqual(other.rules.first?.isEnabled, false)

        // Importing the same file again refreshes the rule instead of cloning it.
        let again = try other.importData(data)
        XCTAssertEqual(again.added, 0)
        XCTAssertEqual(again.updated, 1)
        XCTAssertEqual(other.rules.count, 1)
    }

    func testRulesWithoutEnabledFlagStillLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectionBlockRuleStore(directory: root)
        let legacy =
            #"[{"id":""# + UUID().uuidString
            + #"","scope":"process","value":"safari","createdAt":780000000}]"#
        store.save([])
        let url = root.appendingPathComponent("block-rules.json")
        try Data(legacy.utf8).write(to: url, options: .atomic)
        let rules = store.load()
        XCTAssertEqual(rules.count, 1)
        XCTAssertTrue(rules.first?.isEnabled ?? false)
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
