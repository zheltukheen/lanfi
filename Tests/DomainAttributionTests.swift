import Foundation
import XCTest

final class DomainAttributionTests: XCTestCase {
    func testNormalizeKeepsOnlyTheHost() {
        XCTAssertEqual(
            DomainAttributionRules.normalize("Example.COM:443"), "example.com")
        XCTAssertEqual(
            DomainAttributionRules.normalize("https://api.example.com/v1?token=secret"),
            "api.example.com")
        XCTAssertEqual(
            DomainAttributionRules.normalize("cdn.example.com."), "cdn.example.com")
        XCTAssertEqual(
            DomainAttributionRules.normalize("[2001:db8::1]:443"), nil)
        XCTAssertNil(DomainAttributionRules.normalize("192.168.1.1"))
        XCTAssertNil(DomainAttributionRules.normalize(""))
        XCTAssertNil(DomainAttributionRules.normalize("-bad.example.com"))
        XCTAssertNil(DomainAttributionRules.normalize("not a host"))
    }

    func testRemoteAddressStripsPortsAndBrackets() {
        XCTAssertEqual(
            DomainAttributionRules.remoteAddress("93.184.216.34:443"), "93.184.216.34")
        XCTAssertEqual(
            DomainAttributionRules.remoteAddress("[2001:db8::1]:443"), "2001:db8::1")
        XCTAssertEqual(
            DomainAttributionRules.remoteAddress("2606:4700:4700::1111"), "2606:4700:4700::1111")
        XCTAssertNil(DomainAttributionRules.remoteAddress("*"))
        XCTAssertNil(DomainAttributionRules.remoteAddress(""))
    }

    func testAttributionRanksTheMostContactedDomain() {
        var attribution = AppDomainAttribution.empty
        attribution.record(app: "Safari", domain: "example.com")
        attribution.record(app: "Safari", domain: "example.com")
        attribution.record(app: "Safari", domain: "cdn.example.net")
        attribution.record(app: "Slack", domain: "slack.com")
        XCTAssertEqual(
            attribution.topDomains(forApp: "Safari").first?.domain, "example.com")
        XCTAssertEqual(attribution.topDomains(forApp: "Safari").first?.hits, 2)
        XCTAssertEqual(attribution.appSummaries().first?.app, "Safari")
    }

    func testAttributionNeverStoresIPsOrPaths() {
        var attribution = AppDomainAttribution.empty
        attribution.record(app: "Safari", domain: "10.0.0.1")
        attribution.record(app: "Safari", domain: "https://example.com/private?q=1")
        XCTAssertEqual(attribution.apps["Safari"]?.keys.sorted(), ["example.com"])
    }

    func testPruneDropsOldObservations() {
        var attribution = AppDomainAttribution.empty
        let old = Date().addingTimeInterval(-8 * 24 * 3600)
        attribution.record(app: "Safari", domain: "old.example.com", at: old)
        attribution.record(app: "Safari", domain: "new.example.com")
        attribution.prune(before: Date().addingTimeInterval(-7 * 24 * 3600))
        XCTAssertEqual(attribution.apps["Safari"]?.keys.sorted(), ["new.example.com"])
    }

    func testCSVHasHostsWithoutURLs() {
        var attribution = AppDomainAttribution.empty
        attribution.record(app: "Safari", domain: "example.com")
        let csv = attribution.csv()
        XCTAssertTrue(csv.hasPrefix("app,domain,hits,last_seen"))
        XCTAssertTrue(csv.contains("Safari,example.com,1"))
        XCTAssertFalse(csv.contains("http"))
    }

    func testOwnProcessIsExcluded() {
        XCTAssertTrue(
            DomainAttributionRules.isOwnProcess(
                "LanFi", pid: Int(ProcessInfo.processInfo.processIdentifier)))
        XCTAssertTrue(DomainAttributionRules.isOwnProcess("lanfi", pid: 1))
        XCTAssertFalse(DomainAttributionRules.isOwnProcess("Safari", pid: 2))
    }

    func testHARIndexUsesServerAddressAndHostOnly() throws {
        let json = """
            {
              "log": {
                "version": "1.2",
                "entries": [
                  {
                    "startedDateTime": "2026-11-22T10:00:00.000Z",
                    "time": 12,
                    "serverIPAddress": "93.184.216.34",
                    "request": {
                      "method": "GET",
                      "url": "https://example.com/path?secret=1",
                      "httpVersion": "HTTP/1.1",
                      "headers": []
                    },
                    "response": {
                      "status": 200,
                      "statusText": "OK",
                      "httpVersion": "HTTP/1.1",
                      "headers": [],
                      "content": { "size": 10, "mimeType": "text/html" }
                    },
                    "timings": { "send": 1, "wait": 5, "receive": 1 }
                  }
                ]
              }
            }
            """
        let traffic = try HARParser.parse(data: Data(json.utf8))
        let index = DomainAttributionRules.httpDomainIndex(from: traffic)
        XCTAssertEqual(index["93.184.216.34"], "example.com")
        XCTAssertFalse(index.values.joined().contains("/path"))
    }
}
