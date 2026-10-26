import XCTest

final class NetworkAnalyzerTests: XCTestCase {

    // MARK: - Scoring

    func testSignalScoreIsMonotonicAndBounded() {
        let values = stride(from: -100, through: -30, by: 5).map(NetworkAnalyzer.signalScore)
        XCTAssertEqual(values.first, 0, "Very weak signals should score 0")
        XCTAssertEqual(values.last, 100, "Very strong signals should score 100")
        for pair in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0, pair.1, "Signal score must not decrease as RSSI improves")
        }
    }

    func testSNRScoreUsesUsefulRange() {
        XCTAssertEqual(NetworkAnalyzer.snrScore(snr: 0), 0)
        XCTAssertEqual(NetworkAnalyzer.snrScore(snr: 40), 100)
        XCTAssertGreaterThan(NetworkAnalyzer.snrScore(snr: 25), NetworkAnalyzer.snrScore(snr: 15))
    }

    func testSecurityScoreRanksModernSecurityHigher() {
        let open = makeNetwork(security: "Open")
        let wep = makeNetwork(security: "WEP")
        let wpa = makeNetwork(security: "WPA Personal")
        let wpa2 = makeNetwork(security: "WPA2 Personal")
        let wpa3 = makeNetwork(security: "WPA3 Personal")

        XCTAssertLessThan(NetworkAnalyzer.securityScore(for: open), NetworkAnalyzer.securityScore(for: wep))
        XCTAssertLessThan(NetworkAnalyzer.securityScore(for: wep), NetworkAnalyzer.securityScore(for: wpa))
        XCTAssertLessThan(NetworkAnalyzer.securityScore(for: wpa), NetworkAnalyzer.securityScore(for: wpa2))
        XCTAssertLessThan(NetworkAnalyzer.securityScore(for: wpa2), NetworkAnalyzer.securityScore(for: wpa3))
    }

    func testWPSAndPMFAffectSecurityScore() {
        let hardened = makeNetwork(security: "WPA3 Personal", wpsEnabled: false, pmfRequired: true)
        let weakened = makeNetwork(security: "WPA2 Personal", wpsEnabled: true, pmfRequired: false)
        XCTAssertGreaterThan(NetworkAnalyzer.securityScore(for: hardened), NetworkAnalyzer.securityScore(for: weakened))
    }

    func testQualityScoreStaysInRangeForExtremes() {
        let strong = makeNetwork(signal: -30, noise: -95, snr: 65, utilization: 0)
        let weak = makeNetwork(signal: -97, noise: -80, snr: 2, utilization: 100)
        let strongReport = NetworkAnalyzer.analyze(networks: [strong])
        let weakReport = NetworkAnalyzer.analyze(networks: [weak])

        XCTAssertTrue((0...100).contains(strongReport.metricsByNetworkId[strong.id]!.qualityScore))
        XCTAssertTrue((0...100).contains(weakReport.metricsByNetworkId[weak.id]!.qualityScore))
        XCTAssertGreaterThan(
            strongReport.metricsByNetworkId[strong.id]!.qualityScore,
            weakReport.metricsByNetworkId[weak.id]!.qualityScore
        )
    }

    // MARK: - Overlap

    func testTwentyMHzChannelsOverlapByFrequencyDistance() {
        let channel1 = makeNetwork(band: .band24, channel: 1, width: 20)
        let channel2 = makeNetwork(band: .band24, channel: 2, width: 20)
        let channel6 = makeNetwork(band: .band24, channel: 6, width: 20)

        XCTAssertEqual(NetworkAnalyzer.overlapFraction(channel1, channel2), 0.75, accuracy: 0.001)
        XCTAssertEqual(NetworkAnalyzer.overlapFraction(channel1, channel6), 0.0, accuracy: 0.001)
    }

    func testDifferentBandsNeverOverlap() {
        let ghz24 = makeNetwork(band: .band24, channel: 1, width: 20)
        let ghz5 = makeNetwork(band: .band5, channel: 36, width: 80)
        XCTAssertEqual(NetworkAnalyzer.overlapFraction(ghz24, ghz5), 0)
    }

    func testWideChannelOverlapsNarrowNeighbours() {
        let wide = makeNetwork(band: .band5, channel: 36, width: 80)
        let narrow = makeNetwork(band: .band5, channel: 40, width: 20)
        XCTAssertGreaterThan(NetworkAnalyzer.overlapFraction(wide, narrow), 0.2)
    }

    func testCongestionGrowsWithNeighbours() {
        let target = makeNetwork(id: "target", channel: 6)
        let neighbour = makeNetwork(id: "neighbour", channel: 6, signal: -50)
        let lone = NetworkAnalyzer.metricsFor(target, among: [target])
        let crowded = NetworkAnalyzer.metricsFor(target, among: [target, neighbour])

        XCTAssertGreaterThan(crowded.interferenceLoad, lone.interferenceLoad)
        XCTAssertLessThan(crowded.congestionScore, lone.congestionScore)
        XCTAssertEqual(crowded.coChannelCount, 1)
        XCTAssertTrue(crowded.issues.contains { $0.title == "Congested channel" })
    }

    // MARK: - Recommendations

    func testRecommendationAvoidsOccupiedChannels() {
        let occupied1 = makeNetwork(id: "a", channel: 1, signal: -45)
        let occupied11 = makeNetwork(id: "b", channel: 11, signal: -45)
        let recommendations = NetworkAnalyzer.recommendations(
            for: .band24,
            among: [occupied1, occupied11]
        )

        XCTAssertEqual(recommendations.first?.channel, 6)
        XCTAssertGreaterThan(recommendations.first?.score ?? 0, 60)
    }

    func testRecommendationFindsQuietFiveGHzChannel() {
        var networks = (36...48).map { channel in
            makeNetwork(id: "busy-\(channel)", band: .band5, channel: channel, width: 20, signal: -40)
        }
        networks.append(makeNetwork(id: "quiet", band: .band5, channel: 149, width: 20, signal: -70))

        let recommendations = NetworkAnalyzer.recommendations(for: .band5, among: networks)
        XCTAssertFalse(recommendations.isEmpty)
        XCTAssertNotEqual(recommendations.first?.channel, 36)
    }

    func testEmptyBandIsScoredAsClear() {
        let recommendations = NetworkAnalyzer.recommendations(for: .band5, among: [])
        XCTAssertEqual(recommendations.first?.score, 100)
    }

    func testWiFi7GenerationIsRecognised() {
        XCTAssertEqual(WiFiStandard.mode11be.label, "11be")
        XCTAssertGreaterThan(WiFiStandard.mode11be.sortOrder, WiFiStandard.mode11ax.sortOrder)
    }

    func testAnalysisIsDeterministic() {
        let networks = [
            makeNetwork(id: "a", channel: 1, signal: -55),
            makeNetwork(id: "b", channel: 6, signal: -70),
        ]
        let first = NetworkAnalyzer.analyze(networks: networks)
        let second = NetworkAnalyzer.analyze(networks: networks)
        XCTAssertEqual(first.averageQuality, second.averageQuality)
        XCTAssertEqual(first.recommendationsByBand[.band24], second.recommendationsByBand[.band24])
    }

    // MARK: - Security findings

    func testOpenNetworkAndWPSBecomeFindings() {
        let open = makeNetwork(ssid: "Cafe", security: "Open", wpsEnabled: true)
        let report = NetworkAnalyzer.analyze(networks: [open])

        XCTAssertTrue(report.securityFindings.contains { $0.title == "Open network" && $0.severity == .critical })
        XCTAssertTrue(report.securityFindings.contains { $0.title == "WPS enabled" })
        XCTAssertEqual(report.criticalFindingCount, 1)
    }

    func testSecureNetworkHasNoCriticalFindings() {
        let secure = makeNetwork(security: "WPA3 Personal", pmfRequired: true)
        let report = NetworkAnalyzer.analyze(networks: [secure])
        XCTAssertEqual(report.criticalFindingCount, 0)
    }

    func testDFSChannelIsLabelled() {
        let recommendations = NetworkAnalyzer.recommendations(
            for: .band5,
            among: [makeNetwork(band: .band5, channel: 100, signal: -45)],
            limit: 100
        )
        XCTAssertTrue(recommendations.contains { $0.isDFS && $0.channel >= 52 && $0.channel <= 144 })
    }
}

// MARK: - Fixtures

func makeNetwork(
    id: String = UUID().uuidString,
    bssid: String = "AA:BB:CC:DD:EE:FF",
    ssid: String = "Test Network",
    band: WiFiBand = .band24,
    channel: Int = 6,
    width: Int = 20,
    generation: WiFiStandard = .mode11ax,
    security: String = "WPA2 Personal",
    signal: Int = -60,
    noise: Int? = -95,
    snr: Int? = 35,
    utilization: Int? = nil,
    wpsEnabled: Bool? = false,
    pmfRequired: Bool? = true
) -> NetworkModel {
    NetworkModel(
        id: id,
        bssid: bssid,
        ssid: ssid,
        band: band,
        channel: channel,
        channelWidthMHz: width,
        generation: generation,
        security: security,
        vendor: "Test Vendor",
        mode: "Infrastructure",
        signal: signal,
        noise: noise,
        snr: snr,
        basicRates: [6, 12, 24],
        minBasicRate: 6,
        maxBasicRate: 24,
        minRate: 6,
        maxRate: 1200,
        centerFrequency: nil,
        channelUtilization: utilization,
        beaconInterval: 100,
        beaconRate: 24,
        beaconAirtime: 1,
        beaconMode: "Infrastructure",
        countryCode: "US",
        fastTransition: false,
        protectionMode: "No protection mode",
        stations: nil,
        clients: nil,
        streams: 2,
        type: "Infrastructure",
        wps: wpsEnabled == true ? "Wi-Fi Protected Setup (WPS)" : "Unknown",
        wpsEnabled: wpsEnabled,
        pmfRequired: pmfRequired,
        ieCount: 10,
        ieTotalLength: 100,
        ratesEstimated: true,
        informationElements: [],
        count: 1,
        firstSeen: Date(timeIntervalSince1970: 0),
        lastSeen: Date(timeIntervalSince1970: 0)
    )
}
