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

    // MARK: - Localized keywords

    private static let locales = ["en", "ru", "de", "fr", "zh-Hans"]

    /// Reads the shipped strings file directly, because the test bundle runs
    /// in the host's language and a Russian query can only be checked against
    /// the Russian table.
    private func strings(for locale: String) throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/\(locale).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return plist as? [String: String] ?? [:]
    }

    func testEverySettingsPageHasKeywordsInEveryLocale() throws {
        for locale in Self.locales {
            let table = try strings(for: locale)
            for section in SettingsSection.allCases {
                let key = "settings.keywords.\(section.rawValue)"
                let value = try XCTUnwrap(table[key], "missing \(key) in \(locale)")
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespaces).isEmpty,
                    "empty \(key) in \(locale)")
            }
        }
    }

    func testRussianKeywordsFindPrivacyAndDiagnostics() throws {
        let table = try strings(for: "ru")
        let privacy = try XCTUnwrap(table["settings.keywords.privacy"])
        let privacyKeywords = privacy.split(separator: ",").map(
            { $0.trimmingCharacters(in: .whitespaces) })
        XCTAssertTrue(
            privacyKeywords.contains { $0.lowercased().contains("анонимная статистика") },
            "Russian Privacy keywords must include «анонимная статистика», got \(privacyKeywords)")

        let diagnostics = try XCTUnwrap(table["settings.keywords.diagnostics"])
        XCTAssertTrue(
            diagnostics.lowercased().contains("бенчмарк резолверов"),
            "Russian Diagnostics keywords must include «бенчмарк резолверов»")
    }

    func testLocalizedKeywordsAreSearchable() throws {
        let russianItem = CommandItem(
            id: "settings.privacy-russian", title: "Конфиденциальность", subtitle: "",
            category: "Настройки", keywords: ["анонимная статистика", "телеметрия"],
            destination: .settings(.privacy))
        let englishItem = CommandItem(
            id: "settings.privacy-english", title: "Privacy", subtitle: "",
            category: "Settings", keywords: ["anonymous statistics"],
            destination: .settings(.privacy))

        XCTAssertEqual(
            CommandIndex.rank(russianItem, query: "анонимная статистика"), 3)
        XCTAssertNil(CommandIndex.rank(englishItem, query: "анонимная статистика"))
        XCTAssertEqual(CommandIndex.rank(englishItem, query: "anonymous statistics"), 3)
    }

    func testKeywordsAreSplitIntoWholePhrases() {
        let keywords = CommandIndex.keywords(for: .privacy)
        XCTAssertFalse(keywords.isEmpty)
        XCTAssertTrue(keywords.contains { $0.lowercased().contains("anonymous statistics") })
        XCTAssertTrue(keywords.allSatisfy { !$0.hasPrefix(" ") && !$0.hasSuffix(" ") })
    }
}
