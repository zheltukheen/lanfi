import XCTest

final class ToolkitModelsTests: XCTestCase {

    // MARK: - ToolTarget

    func testTargetParsesHostAndPort() {
        XCTAssertEqual(ToolTarget.parse("example.com"), ToolTarget(host: "example.com", port: nil))
        XCTAssertEqual(
            ToolTarget.parse("example.com:443"), ToolTarget(host: "example.com", port: 443))
        XCTAssertEqual(
            ToolTarget.parse("https://example.com/path"),
            ToolTarget(host: "example.com", port: nil))
        XCTAssertEqual(
            ToolTarget.parse("https://example.com:8443/path"),
            ToolTarget(host: "example.com", port: 8443))
        XCTAssertEqual(
            ToolTarget.parse("[2001:db8::1]:443"),
            ToolTarget(host: "2001:db8::1", port: 443))
        XCTAssertEqual(
            ToolTarget.parse("2001:db8::1"), ToolTarget(host: "2001:db8::1", port: nil))
    }

    func testTargetRejectsMalformedInput() {
        XCTAssertNil(ToolTarget.parse(""))
        XCTAssertNil(ToolTarget.parse("   "))
        XCTAssertNil(ToolTarget.parse("example.com:0"))
        XCTAssertNil(ToolTarget.parse("example.com:70000"))
        XCTAssertNil(ToolTarget.parse("example.com:abc"))
        XCTAssertNil(ToolTarget.parse("exa mple.com"))
    }

    func testTargetDisplayBracketsIPv6() {
        XCTAssertEqual(ToolTarget(host: "2001:db8::1", port: 443).display, "[2001:db8::1]:443")
        XCTAssertEqual(ToolTarget(host: "example.com", port: 80).display, "example.com:80")
    }

    // MARK: - Ping statistics

    func testPingStatisticsIgnoreLostSamples() {
        let samples = [
            PingSample(sequence: 1, rttMilliseconds: 10),
            PingSample(sequence: 2, rttMilliseconds: 20),
            PingSample(sequence: 3, rttMilliseconds: nil, error: "Timed out"),
            PingSample(sequence: 4, rttMilliseconds: 30),
        ]
        let stats = PingStatistics(host: "example.com", samples: samples)

        XCTAssertEqual(stats.transmitted, 4)
        XCTAssertEqual(stats.received, 3)
        XCTAssertEqual(stats.packetLossPercent, 25, accuracy: 0.001)
        XCTAssertEqual(stats.minMilliseconds, 10)
        XCTAssertEqual(stats.averageMilliseconds, 20)
        XCTAssertEqual(stats.maxMilliseconds, 30)
        XCTAssertEqual(
            try XCTUnwrap(stats.standardDeviationMilliseconds),
            sqrt(200.0 / 3.0),
            accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(stats.jitterMilliseconds), 10, accuracy: 0.0001)
    }

    func testPingStatisticsWithNoRepliesHaveNoRTT() {
        let stats = PingStatistics(
            host: "example.com",
            samples: [
                PingSample(sequence: 1, rttMilliseconds: nil, error: "Timed out"),
                PingSample(sequence: 2, rttMilliseconds: nil, error: "Timed out"),
            ])

        XCTAssertEqual(stats.received, 0)
        XCTAssertEqual(stats.packetLossPercent, 100, accuracy: 0.001)
        XCTAssertNil(stats.averageMilliseconds)
        XCTAssertNil(stats.standardDeviationMilliseconds)
        XCTAssertNil(stats.jitterMilliseconds)
    }

    // MARK: - Subnet calculator

    func testSubnetForSlash24() throws {
        let subnet = try XCTUnwrap(SubnetCalculator.parseCIDR("192.168.1.10/24"))
        XCTAssertEqual(subnet.network.description, "192.168.1.0")
        XCTAssertEqual(subnet.broadcast.description, "192.168.1.255")
        XCTAssertEqual(subnet.netmask.description, "255.255.255.0")
        XCTAssertEqual(subnet.wildcard.description, "0.0.0.255")
        XCTAssertEqual(subnet.firstUsable?.description, "192.168.1.1")
        XCTAssertEqual(subnet.lastUsable?.description, "192.168.1.254")
        XCTAssertEqual(subnet.totalAddresses, 256)
        XCTAssertEqual(subnet.usableHosts, 254)
        XCTAssertEqual(subnet.cidr, "192.168.1.0/24")
    }

    func testSubnetForSlash31AndSlash32() throws {
        let pointToPoint = try XCTUnwrap(SubnetCalculator.parseCIDR("10.0.0.0/31"))
        XCTAssertEqual(pointToPoint.totalAddresses, 2)
        XCTAssertEqual(pointToPoint.usableHosts, 2)
        XCTAssertEqual(pointToPoint.firstUsable?.description, "10.0.0.0")
        XCTAssertEqual(pointToPoint.lastUsable?.description, "10.0.0.1")

        let single = try XCTUnwrap(SubnetCalculator.parseCIDR("10.0.0.5/32"))
        XCTAssertEqual(single.totalAddresses, 1)
        XCTAssertEqual(single.usableHosts, 1)
        XCTAssertEqual(single.firstUsable?.description, "10.0.0.5")
        XCTAssertEqual(single.lastUsable?.description, "10.0.0.5")
    }

    func testSubnetForSlashZero() throws {
        let all = try XCTUnwrap(SubnetCalculator.parseCIDR("0.0.0.0/0"))
        XCTAssertEqual(all.netmask.description, "0.0.0.0")
        XCTAssertEqual(all.broadcast.description, "255.255.255.255")
        XCTAssertEqual(all.totalAddresses, 4_294_967_296)
        XCTAssertEqual(all.usableHosts, 4_294_967_294)
    }

    func testSubnetRejectsInvalidInput() {
        XCTAssertNil(SubnetCalculator.parseCIDR("192.168.1.1"))
        XCTAssertNil(SubnetCalculator.parseCIDR("192.168.1.1/33"))
        XCTAssertNil(SubnetCalculator.parseCIDR("192.168.1.256/24"))
        XCTAssertNil(IPv4Address("1.2.3"))
        XCTAssertNil(IPv4Address("1.2.3.4.5"))
    }

    // MARK: - Port spec

    func testPortSpecExpandsRangesAndSorts() throws {
        XCTAssertEqual(try PortSpec.parse("21-23,25,53"), [21, 22, 23, 25, 53])
        XCTAssertEqual(try PortSpec.parse("443,80,80"), [80, 443])
        XCTAssertEqual(try PortSpec.parse(" 22 , 80 "), [22, 80])
    }

    func testPortSpecRejectsBadInput() {
        XCTAssertThrowsError(try PortSpec.parse(""))
        XCTAssertThrowsError(try PortSpec.parse("0"))
        XCTAssertThrowsError(try PortSpec.parse("65536"))
        XCTAssertThrowsError(try PortSpec.parse("80-70"))
        XCTAssertThrowsError(try PortSpec.parse("abc"))
        XCTAssertThrowsError(try PortSpec.parse("80-"))
    }

    func testPortSpecCapsTheSweep() {
        XCTAssertThrowsError(try PortSpec.parse("1-5000")) { error in
            XCTAssertEqual(error as? PortSpecError, .tooMany(PortSpec.maximumPorts))
        }
    }

    func testPortPresetsAreSortedAndUnique() {
        for preset in PortPreset.allCases {
            XCTAssertEqual(preset.ports, Array(Set(preset.ports)).sorted(), "\(preset)")
        }
    }

    func testCommonServiceNames() {
        XCTAssertEqual(PortServices.name(for: 22), "SSH")
        XCTAssertEqual(PortServices.name(for: 443), "HTTPS")
        XCTAssertNil(PortServices.name(for: 12345))
    }
}
