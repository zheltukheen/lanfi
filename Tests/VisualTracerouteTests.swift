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

    func testLatencyBands() {
        XCTAssertEqual(VisualRouteLatency.band(for: 12), .fast)
        XCTAssertEqual(VisualRouteLatency.band(for: 39.9), .fast)
        XCTAssertEqual(VisualRouteLatency.band(for: 40), .moderate)
        XCTAssertEqual(VisualRouteLatency.band(for: 119), .moderate)
        XCTAssertEqual(VisualRouteLatency.band(for: 120), .slow)
        XCTAssertEqual(VisualRouteLatency.band(for: nil), .unknown)
    }

    func testLinksSkipHopsWithoutLocation() {
        let hops = [
            hop(ttl: 1, latitude: 52.5, longitude: 13.4, milliseconds: 4),
            hop(ttl: 2, latitude: nil, longitude: nil, milliseconds: nil),
            hop(ttl: 3, latitude: 48.8, longitude: 2.3, milliseconds: 22),
            hop(ttl: 4, latitude: 40.7, longitude: -74.0, milliseconds: 90),
        ]
        let links = VisualTraceroutePath.links(for: hops)
        XCTAssertEqual(links.map(\.ttl), [3, 4])
        XCTAssertEqual(links[0].fromLatitude, 52.5)
        XCTAssertEqual(links[0].toLatitude, 48.8)
        XCTAssertEqual(links[0].milliseconds, 22)
        XCTAssertEqual(links[1].toLongitude, -74.0)
    }

    func testOriginBecomesTheFirstLink() throws {
        let origin = GeoIPReport(
            query: "My IP", ip: "203.0.113.9", type: "IPv4", continent: "", country: "DE",
            countryCode: "DE", flag: "", region: "", city: "Berlin", latitude: 52.52,
            longitude: 13.40, asn: nil, organization: "", isp: "", timezone: "", utcOffset: "")
        let hops = [
            hop(ttl: 1, latitude: nil, longitude: nil, milliseconds: nil),
            hop(ttl: 2, latitude: 48.85, longitude: 2.35, milliseconds: 18),
        ]
        let links = VisualTraceroutePath.links(origin: origin, hops: hops)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].ttl, 2)
        XCTAssertEqual(links[0].fromLatitude, 52.52)
        XCTAssertEqual(links[0].toLatitude, 48.85)
    }

    private func hop(
        ttl: Int, latitude: Double?, longitude: Double?, milliseconds: Double?
    ) -> VisualTracerouteHop {
        let geo = latitude.flatMap { latitude in
            longitude.map { longitude in
                GeoIPReport(
                    query: "10.0.0.\(ttl)", ip: "10.0.0.\(ttl)", type: "IPv4", continent: "",
                    country: "", countryCode: "", flag: "", region: "", city: "",
                    latitude: latitude, longitude: longitude, asn: nil, organization: "",
                    isp: "", timezone: "", utcOffset: "")
            }
        }
        return VisualTracerouteHop(
            hop: TracerouteHop(
                ttl: ttl, address: "10.0.0.\(ttl)",
                milliseconds: milliseconds.map { [$0] } ?? []),
            geo: geo)
    }
}
