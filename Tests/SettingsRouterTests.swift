import XCTest

@MainActor
final class SettingsRouterTests: XCTestCase {
    func testRequestedSectionIsDeliveredOnce() {
        let router = SettingsRouter()
        router.request(.privacy)
        XCTAssertEqual(router.pending, .privacy)
        XCTAssertEqual(router.takePending(), .privacy)
        XCTAssertNil(router.pending, "a request must not be replayed on the next appearance")
        XCTAssertNil(router.takePending())
    }

    func testLaterRequestWins() {
        let router = SettingsRouter()
        router.request(.general)
        router.request(.diagnostics)
        XCTAssertEqual(router.takePending(), .diagnostics)
    }

    func testEverySectionCanBeRouted() {
        let router = SettingsRouter()
        for section in SettingsSection.allCases {
            router.request(section)
            XCTAssertEqual(router.takePending(), section)
        }
    }
}
