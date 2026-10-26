import XCTest

final class DeepLinkTests: XCTestCase {
    func testParsesTabs() {
        XCTAssertEqual(DeepLink.parse(URL(string: "lanfi://tab/protocols")!), .tab(1))
        XCTAssertEqual(DeepLink.parse(URL(string: "lanfi://tab/interfaces")!), .interfaces)
        XCTAssertEqual(DeepLink.parse(URL(string: "lanfi://tab/diagnostics")!), .tab(6))
    }

    func testParsesSearchAndDiagnostics() {
        XCTAssertEqual(DeepLink.parse(URL(string: "lanfi://search?q=AX55")!), .search("AX55"))
        XCTAssertEqual(DeepLink.parse(URL(string: "lanfi://diagnostics/run")!), .runDiagnostics)
    }

    func testRejectsOtherSchemes() {
        XCTAssertNil(DeepLink.parse(URL(string: "https://example.com")!))
        XCTAssertNil(DeepLink.parse(URL(string: "lanfi://tab/unknown")!))
    }
}
