import XCTest

final class ServiceDescriptionTests: XCTestCase {
    func testNormalizesHostInput() {
        XCTAssertEqual(
            ServiceDescriptionCatalog.normalizedHost("WWW.Example.COM.:443"), "example.com")
        XCTAssertEqual(
            ServiceDescriptionCatalog.normalizedHost("  gateway.icloud.com  "), "gateway.icloud.com")
        XCTAssertEqual(ServiceDescriptionCatalog.normalizedHost("1.1.1.1:5353"), "1.1.1.1")
        XCTAssertEqual(ServiceDescriptionCatalog.normalizedHost("[::1]:8080"), "[::1]:8080")
    }

    func testExactEntryBeatsSuffix() {
        let push = ServiceDescriptionCatalog.describe(domain: "gateway.icloud.com")
        XCTAssertEqual(push?.title, "Apple push notifications")
        XCTAssertEqual(push?.source, .bundled)

        let iCloud = ServiceDescriptionCatalog.describe(domain: "p123.icloud.com")
        XCTAssertEqual(iCloud?.title, "Apple iCloud sync")
    }

    func testSuffixMatchingAndNormalization() {
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "www.slack.com")?.title, "Slack")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "SLACK.com.")?.title, "Slack")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "api.slack-edge.com")?.title, "Slack")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "dns.google.com")?.title, "Google service")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "www.googleapis.com")?.title,
            "Google APIs")
    }

    func testPublicResolversAndLocalNames() {
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "1.1.1.1")?.title, "Cloudflare public DNS")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "8.8.8.8")?.title, "Google public DNS")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "9.9.9.9")?.title, "Quad9 public DNS")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "printer.local")?.title,
            "Local network device (Bonjour)")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(domain: "localhost")?.title, "This Mac")
    }

    func testUnknownDomainStaysUnknown() {
        XCTAssertNil(ServiceDescriptionCatalog.describe(domain: "unknown.example.invalid"))
        XCTAssertNil(ServiceDescriptionCatalog.describe(domain: ""))
        XCTAssertEqual(ServiceDescription.unknownService.source, .unknown)
        XCTAssertEqual(ServiceDescription.unknownService.title, "Unknown service")
    }

    func testProcessMatchingIsCaseInsensitiveAndPrefixTolerant() {
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(process: "mDNSResponder")?.title,
            "Bonjour / mDNS discovery")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(process: "com.apple.WebKit.Networking")?.title,
            "Web content hosted by an app")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(process: "python3.12")?.title,
            "Python script or server")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(process: "ssh-agent")?.title, "SSH session")
        XCTAssertEqual(
            ServiceDescriptionCatalog.describe(process: "Google Chrome Helper (Renderer)")?.title,
            "Google Chrome")
        XCTAssertNil(ServiceDescriptionCatalog.describe(process: "com.example.unknown"))
        XCTAssertNil(ServiceDescriptionCatalog.describe(process: "   "))
    }

    func testEveryEntryHasACategoryAndTitle() {
        for domain in ["gateway.icloud.com", "swscan.apple.com", "github.com", "youtube.com"] {
            let description = ServiceDescriptionCatalog.describe(domain: domain)
            XCTAssertFalse(description?.title.isEmpty ?? true)
            XCTAssertFalse(description?.category.isEmpty ?? true)
        }
    }
}
