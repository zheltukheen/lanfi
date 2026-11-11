import XCTest

final class SubnetCalculatorTests: XCTestCase {

    func testIPAndNetmaskInput() {
        let subnet = SubnetCalculator.parse("192.168.1.10 255.255.255.0")
        XCTAssertEqual(subnet?.cidr, "192.168.1.0/24")
        XCTAssertEqual(subnet?.netmask.description, "255.255.255.0")
        XCTAssertEqual(subnet?.usableHosts, 254)
    }

    func testCIDRInputStillWorks() {
        XCTAssertEqual(SubnetCalculator.parse("10.0.0.5/20")?.cidr, "10.0.0.0/20")
    }

    func testRejectsNonContiguousNetmask() {
        XCTAssertNil(SubnetCalculator.parse("192.168.1.10 255.0.255.0"))
    }
}
