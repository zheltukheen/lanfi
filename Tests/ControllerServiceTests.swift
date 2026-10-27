import XCTest

final class SNMPControllerTests: XCTestCase {
    func testParsesWalkOutput() {
        let rows = SNMPController.parse("1.3.6.1.2.1.1.1.0 = Test AP\n1.3.6.1.2.1.1.5.0 = Lab")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.name, "Test AP")
    }
}
