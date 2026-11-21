import XCTest

final class RuleTargetsTests: XCTestCase {
    private func running(
        _ name: String, pid: Int = 100, bundle: String? = nil, executable: String? = nil
    ) -> RuleTargetCatalog.RunningProcess {
        RuleTargetCatalog.RunningProcess(
            name: name, pid: pid, bundleIdentifier: bundle, executable: executable ?? name)
    }

    private func bundle(_ name: String, path: String? = nil) -> RuleTargetCatalog.ApplicationBundle {
        RuleTargetCatalog.ApplicationBundle(
            name: name, path: path ?? "/Applications/\(name).app", bundleIdentifier: "com.test.\(name)")
    }

    func testInstalledApplicationBecomesAnApplicationRule() {
        let targets = RuleTargetCatalog.targets(running: [], applications: [bundle("Safari")])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].scope, .application)
        XCTAssertEqual(targets[0].value, "Safari")
        XCTAssertEqual(targets[0].kind, .application)
    }

    func testRunningAppWinsOverItsBundleAndShowsThePID() {
        let targets = RuleTargetCatalog.targets(
            running: [running("Safari", pid: 42, bundle: "com.apple.Safari", executable: "Safari")],
            applications: [bundle("Safari")])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].kind, .running)
        XCTAssertEqual(targets[0].scope, .application)
        XCTAssertTrue(targets[0].detail.contains("42"))
    }

    func testProcessWithoutBundleMatchesItsExecutableName() {
        let targets = RuleTargetCatalog.targets(
            running: [running("com.apple.WebKit.Networking", pid: 9, executable: "com.apple.WebKit.Networking")],
            applications: [])
        XCTAssertEqual(targets[0].scope, .process)
        XCTAssertEqual(targets[0].value, "com.apple.WebKit.Networking")
    }

    func testTargetsAreSortedByName() {
        let targets = RuleTargetCatalog.targets(
            running: [running("Zebra"), running("Amphetamine")],
            applications: [bundle("Music")])
        XCTAssertEqual(targets.map(\.name), ["Amphetamine", "Music", "Zebra"])
    }

    func testSuggestionsSkipListenersAndCoveredApps() {
        let rows = [
            OpenConnection(
                id: "1", process: "Safari", pid: 1, user: "demo", protocolName: "IPv4",
                transport: "TCP", local: "10.0.0.2:5000", remote: "1.1.1.1:443",
                state: "ESTABLISHED"),
            OpenConnection(
                id: "2", process: "Safari", pid: 1, user: "demo", protocolName: "IPv4",
                transport: "TCP", local: "10.0.0.2:5001", remote: "8.8.8.8:443",
                state: "ESTABLISHED"),
            OpenConnection(
                id: "3", process: "Mail", pid: 2, user: "demo", protocolName: "IPv4",
                transport: "TCP", local: "10.0.0.2:5002", remote: "2.2.2.2:993",
                state: "ESTABLISHED"),
            OpenConnection(
                id: "4", process: "nginx", pid: 3, user: "demo", protocolName: "IPv4",
                transport: "TCP", local: "*:8080", remote: "—", state: "LISTEN"),
        ]
        let suggestions = RuleSuggestionBuilder.suggestions(
            connections: rows,
            rules: [ConnectionBlockRule(scope: .application, value: "Mail")])
        XCTAssertEqual(suggestions.map(\.name), ["Safari"])
        XCTAssertEqual(suggestions[0].scope, .application)
        XCTAssertEqual(suggestions[0].value, "Safari")
    }
}
