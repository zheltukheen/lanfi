import XCTest

@testable import LanFiCore

/// The support list is read from the same FUNDING.yml GitHub renders, so the
/// parser is tested against the shapes that file can take.
final class FundingCoreTests: XCTestCase {
    func testInlineCustomListBecomesOptions() throws {
        let options = FundingCatalog.parse(
            """
            # These are supported funding model platforms
            github:
            patreon:
            custom: ['https://boosty.to/zheltukheen', "https://example.com/support"]
            """)

        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0].title, "Boosty")
        XCTAssertEqual(options[0].url.absoluteString, "https://boosty.to/zheltukheen")
        XCTAssertEqual(options[0].icon, "heart.fill")
        XCTAssertEqual(options[1].title, "Example")
        XCTAssertEqual(options[1].detail, "example.com")
    }

    func testBlockCustomListAndComments() {
        let options = FundingCatalog.parse(
            """
            custom:
              # the paid page
              - https://boosty.to/zheltukheen
              - 'https://ko-fi.com/someone'  # trailing comment
            """)
        XCTAssertEqual(options.map(\.title), ["Boosty", "Ko-fi"])
        XCTAssertEqual(
            options.map(\.url.absoluteString),
            [
                "https://boosty.to/zheltukheen", "https://ko-fi.com/someone",
            ])
    }

    func testPlatformKeysBuildTheirDocumentedURLs() throws {
        let options = FundingCatalog.parse(
            """
            github: [alice, bob]
            ko_fi: carol
            buy_me_a_coffee: dave
            polar: erin
            thanks_dev: u/gh/frank
            """)

        XCTAssertEqual(
            options.map(\.url.absoluteString),
            [
                "https://github.com/sponsors/alice",
                "https://github.com/sponsors/bob",
                "https://ko-fi.com/carol",
                "https://www.buymeacoffee.com/dave",
                "https://polar.sh/erin",
                "https://thanks.dev/u/gh/frank",
            ])
        XCTAssertEqual(options[0].title, "GitHub Sponsors")
        XCTAssertEqual(options[2].title, "Ko-fi")
        XCTAssertEqual(options[3].icon, "cup.and.saucer.fill")
    }

    func testPlaceholderKeysAndUnknownPlatformsAreIgnored() {
        let options = FundingCatalog.parse(
            """
            github: # Replace with up to 4 GitHub Sponsors-enabled usernames
            patreon: Replace with a single Patreon username
            mystery: someone
            custom: []
            """)
        XCTAssertTrue(options.isEmpty)
    }

    func testAtPrefixIsStrippedAndURLsAreDeduplicated() {
        let options = FundingCatalog.parse(
            """
            github: @alice
            custom:
              - https://github.com/sponsors/alice
              - https://github.com/sponsors/alice
            """)
        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].account, "alice")
        XCTAssertEqual(options[0].url.absoluteString, "https://github.com/sponsors/alice")
    }

    func testCustomURLWithoutAHostIsRejected() {
        XCTAssertNil(FundingCatalog.option(platform: "custom", value: "not a url"))
        XCTAssertNil(FundingCatalog.option(platform: "custom", value: "ftp://example.com"))
        XCTAssertNotNil(FundingCatalog.option(platform: "custom", value: "https://example.com"))
    }
}
