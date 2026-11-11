import XCTest

final class GeoIPTests: XCTestCase {

    func testParsesSuccessfulReport() throws {
        let json = """
            {
              "ip": "1.1.1.1",
              "success": true,
              "type": "IPv4",
              "continent": "Oceania",
              "continent_code": "OC",
              "country": "Australia",
              "country_code": "AU",
              "region": "Queensland",
              "city": "Brisbane",
              "latitude": -27.4679371,
              "longitude": 153.0280882,
              "connection": {
                "asn": 13335,
                "org": "Apnic Research And Development",
                "isp": "Cloudflare, Inc.",
                "domain": "cloudflare.com"
              },
              "timezone": {"id": "Australia/Brisbane", "utc": "+10:00"}
            }
            """
        let report = try GeoIPParser.parse(Data(json.utf8), query: "1.1.1.1")
        XCTAssertEqual(report.ip, "1.1.1.1")
        XCTAssertEqual(report.city, "Brisbane")
        XCTAssertEqual(report.countryCode, "AU")
        XCTAssertEqual(report.asn, 13335)
        XCTAssertEqual(report.isp, "Cloudflare, Inc.")
        XCTAssertEqual(report.timezone, "Australia/Brisbane")
    }

    func testRejectsUnsuccessfulResponse() {
        let json = #"{"success":false,"message":"404 not found"}"#
        XCTAssertThrowsError(
            try GeoIPParser.parse(Data(json.utf8), query: "example.com")
        ) { error in
            XCTAssertEqual(error as? GeoIPError, .lookupFailed("404 not found"))
        }
    }
}
