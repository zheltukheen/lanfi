import XCTest

final class RoamingAnalyzerTests: XCTestCase {
    private func sample(_ bssid: String, rssi: Int, at seconds: TimeInterval) -> MonitorSample {
        let network = makeNetwork(bssid: bssid, band: .band5, channel: 44, signal: rssi)
        return MonitorSample(network: network, at: Date(timeIntervalSince1970: seconds))
    }

    func testCapabilityBitsComeFromInformationElements() {
        let network = makeNetwork(
            informationElements: [
                InformationElement(
                    id: "70", elementId: 70, length: 5, name: "RM Enabled Capabilities",
                    summary: "", detailLines: [], rawHex: ""),
                InformationElement(
                    id: "54", elementId: 54, length: 3, name: "Mobility Domain",
                    summary: "", detailLines: [], rawHex: ""),
            ])
        let capabilities = RoamingAnalyzer.capabilities(for: network)
        XCTAssertTrue(capabilities.radioMeasurements)
        XCTAssertTrue(capabilities.bssTransition)
        XCTAssertFalse(capabilities.fastTransition)
        XCTAssertEqual(capabilities.supportedCount, 2)
    }

    func testTransitionsFollowBSSIDChangesInTimeOrder() {
        let samples = [
            sample("AA:00:00:00:00:01", rssi: -72, at: 1),
            sample("AA:00:00:00:00:01", rssi: -70, at: 0),
            sample("AA:00:00:00:00:02", rssi: -55, at: 2),
        ]
        let transitions = RoamingAnalyzer.transitions(from: samples)
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].fromBSSID, "AA:00:00:00:00:01")
        XCTAssertEqual(transitions[0].toBSSID, "AA:00:00:00:00:02")
        XCTAssertEqual(transitions[0].strengthDelta, 17)
        XCTAssertFalse(transitions[0].isFailure)
    }

    func testFailedRoamIsDetected() {
        let samples = [
            sample("AA:00:00:00:00:01", rssi: -50, at: 0),
            sample("AA:00:00:00:00:02", rssi: -82, at: 60),
        ]
        XCTAssertEqual(RoamingAnalyzer.transitions(from: samples).first?.isFailure, true)
    }

    func testWeakConnectedClientWithStrongerSiblingIsSticky() {
        let connected = makeNetwork(
            bssid: "AA:00:00:00:00:01", band: .band5, channel: 44, signal: -78)
        let better = makeNetwork(
            bssid: "AA:00:00:00:00:02", band: .band5, channel: 44, signal: -60)
        let verdicts = RoamingAnalyzer.verdicts(connected: connected, visible: [connected, better])
        XCTAssertEqual(verdicts.map(\.kind), [.sticky])
    }

    func testStrongConnectedClientHasNoVerdicts() {
        let connected = makeNetwork(bssid: "AA:00:00:00:00:01", signal: -52)
        XCTAssertTrue(RoamingAnalyzer.verdicts(connected: connected, visible: [connected]).isEmpty)
    }

    func testBandSteeringOpportunityOn24GHz() {
        let connected = makeNetwork(
            bssid: "AA:00:00:00:00:01", band: .band24, channel: 6, signal: -60)
        let five = makeNetwork(bssid: "AA:00:00:00:00:02", band: .band5, channel: 44, signal: -50)
        let verdicts = RoamingAnalyzer.verdicts(connected: connected, visible: [connected, five])
        XCTAssertEqual(verdicts.map(\.kind), [.bandSteering])
    }

    func testAssessmentWithoutConnectedNetworkIsNil() {
        XCTAssertNil(RoamingAnalyzer.assess(connected: nil, visible: [], samples: []))
    }
}

final class LinkTelemetryTests: XCTestCase {
    func testSummaryOfRates() {
        let start = Date(timeIntervalSince1970: 0)
        let samples = [
            LinkRateSample(at: start, rateMbps: 300),
            LinkRateSample(at: start.addingTimeInterval(5), rateMbps: 900),
            LinkRateSample(at: start.addingTimeInterval(10), rateMbps: 600),
        ]
        let summary = LinkTelemetrySummary.make(samples: samples)
        XCTAssertEqual(summary.sampleCount, 3)
        XCTAssertEqual(summary.rateMin, 300)
        XCTAssertEqual(summary.rateMax, 900)
        XCTAssertEqual(summary.rateAverage ?? 0, 600, accuracy: 0.001)
        XCTAssertEqual(summary.latest?.rateMbps, 600)
    }

    func testEmptySummary() {
        XCTAssertEqual(LinkTelemetrySummary.make(samples: []), .empty)
        XCTAssertEqual(LinkTelemetryPresentation.rate(nil), "—")
    }

    func testNSSIsLabelledAsCapability() {
        XCTAssertEqual(LinkTelemetryPresentation.nssCapability(streams: 1), "1 stream (capability)")
        XCTAssertEqual(LinkTelemetryPresentation.nssCapability(streams: 4), "4 streams (capability)")
        XCTAssertEqual(LinkTelemetryPresentation.nssCapability(streams: nil), "—")
    }
}

final class KnownNetworkTests: XCTestCase {
    func testParserDropsHeaderBlankLinesAndIndentation() {
        let output = """
            Preferred networks on en0:
            \tHomeNet
            Office-5G

            Guest
            """
        XCTAssertEqual(KnownNetworksParser.parse(output), ["HomeNet", "Office-5G", "Guest"])
    }

    func testQRPayloadEscapesSpecials() {
        XCTAssertEqual(
            WiFiQRPayload.string(ssid: "Cafe;Guest", password: "p:a,ss\"word", security: .wpa),
            #"WIFI:T:WPA;S:Cafe\;Guest;P:p\:a\,ss\"word;;"#)
    }

    func testOpenNetworkOmitsPassword() {
        XCTAssertEqual(
            WiFiQRPayload.string(ssid: "Lobby", password: "ignored", security: .open),
            "WIFI:T:nopass;S:Lobby;;")
    }
}

final class CombinedReportTests: XCTestCase {
    func testBuilderIncludesScanFindingsAndEscapesHTML() {
        let network = makeNetwork(
            bssid: "AA:BB:CC:DD:EE:01", ssid: "Cafe <Guest>", security: "Open", signal: -58)
        let report = CombinedReportBuilder.make(
            generatedAt: Date(timeIntervalSince1970: 0),
            networks: [network],
            analysis: .empty,
            survey: nil,
            diagnostics: nil,
            speedTests: [],
            events: []
        )
        XCTAssertEqual(report.networkCount, 1)
        XCTAssertEqual(report.scan.first?.ssid, "Cafe <Guest>")

        let html = CombinedReportExporter.html(for: report)
        XCTAssertTrue(html.contains("Cafe &lt;Guest&gt;"))
        XCTAssertFalse(html.contains("Cafe <Guest>"))
        XCTAssertTrue(html.contains("LanFi combined report"))
        XCTAssertTrue(html.contains("Scan"))
    }

    func testEscapeHandlesAmpersandsAndQuotes() {
        XCTAssertEqual(CombinedReportExporter.escape("a&b <c> \"d\""), "a&amp;b &lt;c&gt; &quot;d&quot;")
    }

    func testSpeedRowsKeepNewestLast() {
        let old = ThroughputMeasurement(
            report: ThroughputReport(
                downloadMbps: 100, uploadMbps: 20, latencyMilliseconds: 12,
                responsiveness: nil, testedAt: Date(timeIntervalSince1970: 10)))
        let new = ThroughputMeasurement(
            report: ThroughputReport(
                downloadMbps: 200, uploadMbps: 30, latencyMilliseconds: 9,
                responsiveness: nil, testedAt: Date(timeIntervalSince1970: 20)))
        let report = CombinedReportBuilder.make(
            networks: [], analysis: .empty, survey: nil, diagnostics: nil,
            speedTests: [old, new], events: [])
        XCTAssertEqual(report.speedTests.count, 2)
        XCTAssertEqual(report.speedTests.first?.downloadMbps, 100)
        XCTAssertTrue(CombinedReportExporter.html(for: report).contains("200"))
    }
}
