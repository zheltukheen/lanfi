import XCTest

final class TracerouteParserTests: XCTestCase {

    // MARK: - Hops

    func testSingleProbeStars() throws {
        let output = """
            traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 52 byte packets
             1  192.168.1.1  2.123 ms
             2  *
             3  10.0.0.1  5.100 ms
            """
        let report = TracerouteParser.parse(output, host: "1.1.1.1")

        XCTAssertEqual(report.host, "1.1.1.1")
        XCTAssertEqual(report.hops.map(\.ttl), [1, 2, 3])
        XCTAssertTrue(report.reachedTarget)

        let first = try XCTUnwrap(report.hops.first)
        XCTAssertEqual(first.address, "192.168.1.1")
        XCTAssertNil(first.hostname)
        XCTAssertEqual(try XCTUnwrap(first.milliseconds.first), 2.123, accuracy: 0.0001)
        XCTAssertFalse(first.timedOut)

        let second = try XCTUnwrap(report.hops.dropFirst().first)
        XCTAssertNil(second.address)
        XCTAssertNil(second.hostname)
        XCTAssertTrue(second.milliseconds.isEmpty)
        XCTAssertTrue(second.timedOut)

        let last = try XCTUnwrap(report.hops.last)
        XCTAssertEqual(last.address, "10.0.0.1")
        XCTAssertEqual(try XCTUnwrap(last.milliseconds.first), 5.1, accuracy: 0.0001)
    }

    func testMultipleProbeTimes() throws {
        let output = """
             1  router.local (192.168.1.1)  1.2 ms  1.4 ms  1.5 ms
            """
        let hop = try XCTUnwrap(TracerouteParser.parse(output, host: "192.168.1.1").hops.first)

        XCTAssertEqual(hop.milliseconds.count, 3)
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.first), 1.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.dropFirst().first), 1.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.last), 1.5, accuracy: 0.0001)
    }

    func testHostnameAndAddress() throws {
        let output = """
             1  router.local (192.168.1.1)  1.2 ms
            """
        let hop = try XCTUnwrap(TracerouteParser.parse(output, host: "192.168.1.1").hops.first)

        XCTAssertEqual(hop.hostname, "router.local")
        XCTAssertEqual(hop.address, "192.168.1.1")
        XCTAssertFalse(hop.timedOut)
    }

    func testAllStarHopTimesOut() throws {
        let output = """
            traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 52 byte packets
             6  * * *
            """
        let report = TracerouteParser.parse(output, host: "1.1.1.1")
        let hop = try XCTUnwrap(report.hops.first)

        XCTAssertEqual(report.hops.count, 1)
        XCTAssertEqual(hop.ttl, 6)
        XCTAssertNil(hop.address)
        XCTAssertNil(hop.hostname)
        XCTAssertTrue(hop.milliseconds.isEmpty)
        XCTAssertTrue(hop.timedOut)
        XCTAssertFalse(report.reachedTarget)
    }

    func testTrailingICMPMarkerIsNotATime() throws {
        let output = """
             7  203.0.113.17 (203.0.113.17)  41.3 ms !H
            """
        let hop = try XCTUnwrap(TracerouteParser.parse(output, host: "203.0.113.17").hops.first)

        XCTAssertEqual(hop.address, "203.0.113.17")
        XCTAssertEqual(hop.hostname, "203.0.113.17")
        XCTAssertEqual(hop.milliseconds.count, 1)
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.first), 41.3, accuracy: 0.0001)
        XCTAssertFalse(hop.timedOut)
    }

    func testHeaderOnlyOutputHasNoHops() {
        let output = """
            traceroute to 1.1.1.1 (1.1.1.1), 30 hops max, 52 byte packets
            """
        let report = TracerouteParser.parse(output, host: "1.1.1.1")

        XCTAssertEqual(report.host, "1.1.1.1")
        XCTAssertTrue(report.hops.isEmpty)
        XCTAssertFalse(report.reachedTarget)
    }

    func testMalformedLinesAreIgnored() throws {
        let output = """
            traceroute to example.com (93.184.216.34), 30 hops max, 52 byte packets
            garbage 1.2.3.4 1.0 ms
             1  192.168.1.1  2.123 ms
            not a hop
             ttl  10.0.0.1  3.0 ms
            """
        let report = TracerouteParser.parse(output, host: "example.com")

        XCTAssertEqual(report.hops.count, 1)
        let hop = try XCTUnwrap(report.hops.first)
        XCTAssertEqual(hop.ttl, 1)
        XCTAssertEqual(hop.address, "192.168.1.1")
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.first), 2.123, accuracy: 0.0001)
    }

    func testIPv6Address() throws {
        let output = """
             2  2001:4860:4860::8888  12.5 ms
            """
        let hop = try XCTUnwrap(
            TracerouteParser.parse(output, host: "2001:4860:4860::8888").hops.first)

        XCTAssertEqual(hop.ttl, 2)
        XCTAssertEqual(hop.address, "2001:4860:4860::8888")
        XCTAssertNil(hop.hostname)
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.first), 12.5, accuracy: 0.0001)
        XCTAssertFalse(hop.timedOut)
    }

    func testDuplicateTTLKeepsFirstHop() throws {
        let output = """
             1  192.168.1.1  2.0 ms
             1  10.0.0.1  3.0 ms
            """
        let report = TracerouteParser.parse(output, host: "1.1.1.1")

        XCTAssertEqual(report.hops.count, 1)
        let hop = try XCTUnwrap(report.hops.first)
        XCTAssertEqual(hop.ttl, 1)
        XCTAssertEqual(hop.address, "192.168.1.1")
        XCTAssertEqual(try XCTUnwrap(hop.milliseconds.first), 2.0, accuracy: 0.0001)
    }
}
