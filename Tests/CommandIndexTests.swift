import XCTest

final class CommandIndexTests: XCTestCase {
    func testEmptyQueryListsNothing() {
        XCTAssertTrue(CommandIndex.results(for: "").isEmpty)
        XCTAssertTrue(CommandIndex.results(for: "   ").isEmpty)
    }

    func testExactTitleBeatsPrefixAndSubstring() {
        let results = CommandIndex.results(for: "Ping")
        XCTAssertEqual(results.first?.title, "Ping")
        XCTAssertEqual(results.first?.destination, .tool(.ping))
    }

    func testTitleMatchBeatsKeywordMatch() {
        // "Spectrum" is a tool title and a settings keyword (Hardware).
        let results = CommandIndex.results(for: "Spectrum")
        guard let first = results.first else {
            return XCTFail("expected a match")
        }
        if case .settings = first.destination {
            XCTFail("a title match must outrank a keyword match, got \(first.id)")
        }
    }

    func testKeywordsReachSettingsPages() {
        let statistics = CommandIndex.results(for: "anonymous statistics")
        XCTAssertEqual(statistics.first?.destination, .settings(.privacy))

        let benchmark = CommandIndex.results(for: "resolver benchmark")
        XCTAssertEqual(benchmark.first?.destination, .settings(.diagnostics))
    }

    func testEverySidebarToolIsIndexedOnce() {
        let indexed = CommandIndex.all.filter { item in
            if case .tool = item.destination { return true }
            return false
        }
        let expected = ToolboxTool.allCases.filter { $0.isAvailable && $0.showsInSidebar }
        XCTAssertEqual(indexed.count, expected.count)
        XCTAssertEqual(Set(indexed.map(\.id)).count, indexed.count)
        for tool in expected {
            XCTAssertTrue(
                indexed.contains { $0.destination == .tool(tool) },
                "missing palette entry for \(tool.rawValue)")
        }
    }

    func testEverySettingsSectionAndWorkspacePanelIsIndexed() {
        let settings = CommandIndex.all.compactMap { item -> SettingsSection? in
            if case .settings(let section) = item.destination { return section }
            return nil
        }
        XCTAssertEqual(Set(settings), Set(SettingsSection.allCases))

        let panels = CommandIndex.all.filter { item in
            if case .wifiTab = item.destination { return true }
            return false
        }
        XCTAssertEqual(panels.count, 8)
        XCTAssertEqual(Set(panels.map(\.id)).count, panels.count)
    }

    func testResultsRespectTheLimit() {
        let results = CommandIndex.results(for: "o", limit: 3)
        XCTAssertLessThanOrEqual(results.count, 3)
        XCTAssertFalse(results.isEmpty)
    }

    func testNoMatchReturnsNothing() {
        XCTAssertTrue(CommandIndex.results(for: "zzzzzz").isEmpty)
    }
}
