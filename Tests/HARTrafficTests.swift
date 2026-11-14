import XCTest

final class HARParserTests: XCTestCase {
    func testParsesEntriesTimingsAndCache() throws {
        let traffic = try HARParser.parse(data: Data(SampleHAR.json.utf8))
        XCTAssertEqual(traffic.entries.count, 3)
        XCTAssertEqual(traffic.creator, "Test Browser")
        XCTAssertEqual(traffic.hosts, ["api.example.com", "cdn.example.com"])

        let first = try XCTUnwrap(traffic.entries.first)
        XCTAssertEqual(first.request.method, "GET")
        XCTAssertEqual(first.response.status, 200)
        XCTAssertEqual(first.response.mimeType, "application/json")
        XCTAssertEqual(first.sizeBytes, 1200)
        XCTAssertEqual(first.timings.dns, 10)
        XCTAssertEqual(first.timings.ssl, 30)
        XCTAssertEqual(first.timings.total, 320, accuracy: 0.1)
        XCTAssertNotNil(first.started)
        XCTAssertFalse(first.isFromCache)

        let cached = try XCTUnwrap(traffic.entries.first { $0.host == "cdn.example.com" })
        XCTAssertTrue(cached.isFromCache)
        XCTAssertEqual(cached.response.content.size, 3000)

        let failed = try XCTUnwrap(traffic.entries.last)
        XCTAssertEqual(failed.response.status, 500)
        XCTAssertTrue(failed.isFailure)
        XCTAssertNil(failed.timings.ssl)  // -1 in HAR means "not measured"
        XCTAssertEqual(failed.request.postData?.mimeType, "application/json")
    }

    func testRejectsNonHARJSON() {
        XCTAssertThrowsError(try HARParser.parse(data: Data("{}".utf8))) { error in
            XCTAssertTrue(error.localizedDescription.contains("log"))
        }
    }

    func testRejectsBrokenJSON() {
        XCTAssertThrowsError(try HARParser.parse(data: Data("nope".utf8)))
    }

    func testEmptyEntriesIsValid() throws {
        let traffic = try HARParser.parse(
            data: Data(#"{"log":{"version":"1.2","entries":[]}}"#.utf8))
        XCTAssertTrue(traffic.entries.isEmpty)
    }
}

final class HARTrafficAnalyzerTests: XCTestCase {
    private func traffic() throws -> HARTraffic {
        try HARParser.parse(data: Data(SampleHAR.json.utf8))
    }

    func testSummaryMetrics() throws {
        let insights = HARTrafficAnalyzer.insights(for: try traffic())
        XCTAssertEqual(insights.requestCount, 3)
        XCTAssertEqual(insights.failureCount, 1)
        XCTAssertEqual(insights.cachedCount, 1)
        XCTAssertEqual(insights.transferBytes, 2600)
        XCTAssertEqual(insights.p95Milliseconds, 1200, accuracy: 0.1)
        XCTAssertEqual(insights.averageMilliseconds, 521.67, accuracy: 0.1)
        XCTAssertEqual(insights.slowest.first?.response.status, 500)
        XCTAssertEqual(insights.statusCounts.map(\.code), [200, 500])
        XCTAssertEqual(insights.statusCounts.first?.count, 2)
    }

    func testHostsSortedByTransferredBytes() throws {
        let insights = HARTrafficAnalyzer.insights(for: try traffic())
        XCTAssertEqual(insights.hosts.first?.host, "api.example.com")
        XCTAssertEqual(insights.hosts.first?.requests, 2)
        XCTAssertEqual(insights.hosts.first?.failures, 1)
        XCTAssertEqual(insights.hosts.first?.bytes, 1700)
    }

    func testSlowestPhaseIsTheAverageAcrossEntries() throws {
        let insights = HARTrafficAnalyzer.insights(for: try traffic())
        XCTAssertEqual(insights.slowestPhase?.name, "Wait")
        XCTAssertEqual(insights.slowestPhase?.milliseconds ?? 0, 463.33, accuracy: 0.1)
    }

    func testPercentileRanks() {
        XCTAssertEqual(HARTrafficAnalyzer.percentile([10, 20, 30, 40], fraction: 0.95), 40)
        XCTAssertEqual(HARTrafficAnalyzer.percentile([10, 20, 30, 40], fraction: 0.5), 20)
        XCTAssertEqual(HARTrafficAnalyzer.percentile([], fraction: 0.95), 0)
    }

    func testMarkdownReportMentionsHostsAndRedacts() throws {
        let report = HARTrafficAnalyzer.markdownReport(for: try traffic(), redacted: true)
        XCTAssertTrue(report.contains("# HTTP traffic report"))
        XCTAssertTrue(report.contains("api.example.com"))
        XCTAssertTrue(report.contains("Slowest requests"))
        XCTAssertTrue(report.contains(HARRedaction.placeholder))
        XCTAssertFalse(report.contains("Bearer abc123"))
        XCTAssertFalse(report.contains("secret123"))
    }
}

final class HARRedactionTests: XCTestCase {
    func testAuthorizationBecomesSchemeOnly() {
        let redacted = HARRedaction.headers([
            HARHeader(name: "Authorization", value: "Bearer abc123"),
            HARHeader(name: "Accept", value: "application/json"),
        ])
        XCTAssertEqual(redacted.first?.value, "Bearer \(HARRedaction.placeholder)")
        XCTAssertEqual(redacted.last?.value, "application/json")
    }

    func testCookieValueIsFullyMasked() {
        let redacted = HARRedaction.headers([HARHeader(name: "Cookie", value: "sid=1")])
        XCTAssertEqual(redacted.first?.value, HARRedaction.placeholder)
    }

    func testQueryCredentialsAreRedactedButOtherParametersSurvive() {
        let url = HARRedaction.url("https://api.test/v1?token=abc&page=2&api_key=zzz")
        XCTAssertFalse(url.contains("abc"))
        XCTAssertFalse(url.contains("zzz"))
        XCTAssertTrue(url.contains("page=2"))
    }

    func testJSONBodyRedactsPassword() {
        let body = HARRedaction.body(#"{"user":"ann","password":"hunter2","nested":{"access_token":"t"}}"#)
        XCTAssertFalse(body.contains("hunter2"))
        XCTAssertTrue(body.contains("ann"))
        XCTAssertTrue(body.contains(HARRedaction.placeholder))
    }
}

final class HARExportTests: XCTestCase {
    func testCurlBuildsMethodHeadersAndBody() throws {
        let traffic = try HARParser.parse(data: Data(SampleHAR.json.utf8))
        let login = try XCTUnwrap(traffic.entries.last)
        let command = HARExport.curl(for: login, redacted: true)
        XCTAssertTrue(command.hasPrefix("curl -X POST 'https://api.example.com/v1/login'"))
        XCTAssertTrue(command.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(command.contains("--data-raw"))
        XCTAssertFalse(command.contains("hunter2"))
        XCTAssertFalse(command.contains("-H ':method"))
    }

    func testCurlQuotesSingleQuotes() throws {
        let traffic = try HARParser.parse(data: Data(SampleHAR.json.utf8))
        var entry = try XCTUnwrap(traffic.entries.first)
        entry = HAREntry(
            id: entry.id, started: entry.started, duration: entry.duration,
            serverIP: entry.serverIP, connection: entry.connection,
            request: HARRequest(
                method: "GET", url: "https://x.test/it's", httpVersion: "HTTP/1.1",
                headers: [], query: [], cookies: [], postData: nil),
            response: entry.response, timings: entry.timings, isFromCache: false)
        let command = HARExport.curl(for: entry, redacted: false)
        XCTAssertTrue(command.contains("'https://x.test/it'\\''s'"))
    }

    func testCSVHasOneLinePerEntryAndRedactsPaths() throws {
        let traffic = try HARParser.parse(data: Data(SampleHAR.json.utf8))
        let csv = HARExport.csv(for: traffic.entries, redacted: true)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("started,method,status"))
        XCTAssertFalse(csv.contains("secret123"))
    }
}

// MARK: - Fixture

private enum SampleHAR {
    static let json = """
        {
          "log": {
            "version": "1.2",
            "creator": { "name": "Test Browser", "version": "1.0" },
            "entries": [
              {
                "startedDateTime": "2026-11-14T10:00:00.100Z",
                "time": 320,
                "request": {
                  "method": "GET",
                  "url": "https://api.example.com/v1/items?token=secret123&page=2",
                  "httpVersion": "HTTP/1.1",
                  "headers": [
                    { "name": "Authorization", "value": "Bearer abc123" },
                    { "name": "Accept", "value": "application/json" }
                  ],
                  "queryString": [
                    { "name": "token", "value": "secret123" },
                    { "name": "page", "value": "2" }
                  ]
                },
                "response": {
                  "status": 200,
                  "statusText": "OK",
                  "httpVersion": "HTTP/1.1",
                  "headers": [{ "name": "Content-Type", "value": "application/json" }],
                  "content": { "size": 5000, "mimeType": "application/json" },
                  "bodySize": 1200
                },
                "cache": {},
                "timings": {
                  "blocked": 0, "dns": 10, "connect": 20, "ssl": 30,
                  "send": 1, "wait": 200, "receive": 59
                }
              },
              {
                "startedDateTime": "2026-11-14T10:00:00.500Z",
                "time": 45,
                "request": {
                  "method": "GET",
                  "url": "https://cdn.example.com/app.js",
                  "httpVersion": "HTTP/2",
                  "headers": []
                },
                "response": {
                  "status": 200,
                  "httpVersion": "HTTP/2",
                  "headers": [],
                  "content": { "size": 3000, "mimeType": "application/javascript" },
                  "bodySize": 900
                },
                "cache": {
                  "beforeRequest": { "expires": "2026-11-14T11:00:00.000Z" }
                },
                "timings": {
                  "blocked": 1, "dns": -1, "connect": -1, "ssl": -1,
                  "send": 1, "wait": 40, "receive": 3
                }
              },
              {
                "startedDateTime": "2026-11-14T10:00:01.000Z",
                "time": 1200,
                "request": {
                  "method": "POST",
                  "url": "https://api.example.com/v1/login",
                  "httpVersion": "HTTP/1.1",
                  "headers": [{ "name": "Content-Type", "value": "application/json" }],
                  "postData": {
                    "mimeType": "application/json",
                    "text": "{\\"user\\":\\"ann\\",\\"password\\":\\"hunter2\\"}"
                  }
                },
                "response": {
                  "status": 500,
                  "statusText": "Internal Server Error",
                  "httpVersion": "HTTP/1.1",
                  "headers": [],
                  "content": { "size": 100, "mimeType": "text/plain" },
                  "bodySize": 500
                },
                "cache": {},
                "timings": {
                  "blocked": 20, "dns": 5, "connect": 10, "ssl": -1,
                  "send": 0, "wait": 1150, "receive": 15
                }
              }
            ]
          }
        }
        """
}
