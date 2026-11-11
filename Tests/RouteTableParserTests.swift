import XCTest

final class RouteTableParserTests: XCTestCase {

    func testParsesIPv4Routes() {
        let text = """
            Routing tables

            Internet:
            Destination        Gateway            Flags        Netif Expire
            default            192.168.0.1        UGScg        en0
            127                127.0.0.1          UCS          lo0
            192.168.0          link#5             UCS          en0      !
            192.168.0.1        10:27:f5:a6:2d:52  UHLWIir     en0      1190
            """
        let routes = RouteTableParser.parse(text)
        XCTAssertEqual(routes.count, 4)
        XCTAssertEqual(routes[0].destination, "default")
        XCTAssertEqual(routes[0].gateway, "192.168.0.1")
        XCTAssertEqual(routes[0].interface, "en0")
        XCTAssertTrue(routes[0].isDefault)
        XCTAssertEqual(routes[2].flags, "UCS")
    }
}
