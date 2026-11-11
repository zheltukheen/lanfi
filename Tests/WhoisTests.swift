import XCTest

final class WhoisTests: XCTestCase {

    func testParsesRDAPDomain() throws {
        let json = """
            {
              "objectClassName": "domain",
              "ldhName": "EXAMPLE.COM",
              "handle": "D123",
              "status": ["client transfer prohibited"],
              "events": [
                {"eventAction": "registration", "eventDate": "1995-08-14T04:00:00Z"},
                {"eventAction": "expiration", "eventDate": "2027-08-13T04:00:00Z"},
                {"eventAction": "last changed", "eventDate": "2026-08-14T08:01:43Z"}
              ],
              "nameservers": [
                {"ldhName": "ELLIOTT.NS.CLOUDFLARE.COM"},
                {"ldhName": "HERA.NS.CLOUDFLARE.COM"}
              ],
              "entities": [
                {
                  "roles": ["registrar"],
                  "vcardArray": ["vcard", [
                    ["version", {}, "text", "4.0"],
                    ["fn", {}, "text", "Example Registrar"]
                  ]]
                }
              ]
            }
            """
        let report = try WhoisParser.parse(Data(json.utf8), query: "example.com")
        XCTAssertEqual(report.name, "EXAMPLE.COM")
        XCTAssertEqual(report.registrar, "Example Registrar")
        XCTAssertEqual(report.statuses, ["client transfer prohibited"])
        XCTAssertEqual(report.nameservers.count, 2)
        XCTAssertNotNil(report.registrationDate)
        XCTAssertNotNil(report.expirationDate)
    }

    func testRejectsInvalidJSON() {
        XCTAssertThrowsError(
            try WhoisParser.parse(Data("nope".utf8), query: "example.com")
        ) { error in
            XCTAssertEqual(error as? WhoisError, .invalidResponse)
        }
    }
}
