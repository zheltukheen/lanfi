import XCTest

final class VisualTracerouteTests: XCTestCase {

    func testOnlyPublicAddressesAreGeolocated() {
        XCTAssertTrue(VisualTracerouteFilter.isPublic("1.1.1.1"))
        XCTAssertTrue(VisualTracerouteFilter.isPublic("8.8.8.8"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("192.168.0.1"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("10.0.0.1"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("172.16.5.4"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("127.0.0.1"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("169.254.1.1"))
        XCTAssertFalse(VisualTracerouteFilter.isPublic("not-an-ip"))
    }
}
