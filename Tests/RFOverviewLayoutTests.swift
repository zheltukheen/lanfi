import XCTest

final class RFOverviewLayoutTests: XCTestCase {
    func testCenterFrequencyPerBand() {
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 1, band: .band24), 2407)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 6, band: .band24), 2432)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 14, band: .band24), 2484)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 36, band: .band5), 5180)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 149, band: .band5), 5745)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 37, band: .band6), 6135)
        XCTAssertEqual(RFBandGeometry.centerFrequencyMHz(channel: 233, band: .band6), 7115)
        XCTAssertNil(RFBandGeometry.centerFrequencyMHz(channel: 0, band: .band5))
        XCTAssertNil(RFBandGeometry.centerFrequencyMHz(channel: 300, band: .band5))
    }

    func testTickChannelsAreSortedAndInsideTheBand() {
        for band in [WiFiBand.band24, .band5, .band6] {
            let ticks = RFBandGeometry.tickChannels(for: band)
            XCTAssertFalse(ticks.isEmpty)
            XCTAssertEqual(ticks, ticks.sorted())
            for channel in ticks {
                XCTAssertNotNil(RFBandGeometry.centerFrequencyMHz(channel: channel, band: band))
            }
        }
    }

    func testCoChannelNetworksOverlapCompletely() {
        let layout = RFOverviewLayout.build(
            band: .band5,
            networks: [
                makeNetwork(id: "a", channel: 36, width: 20),
                makeNetwork(id: "b", channel: 36, width: 20),
            ],
            connectedBSSID: nil,
            recommendation: nil
        )

        XCTAssertEqual(layout.spans.count, 2)
        XCTAssertEqual(layout.spans.map(\.overlapCount), [1, 1])
        XCTAssertEqual(layout.hotRegions.count, 1)
        XCTAssertEqual(layout.hotRegions.first?.depth, 2)
        XCTAssertEqual(layout.maxDepth, 2)
        XCTAssertEqual(layout.busiestChannel, 36)
    }

    func testAdjacent5GHzChannelsDoNotOverlap() {
        let layout = RFOverviewLayout.build(
            band: .band5,
            networks: [
                makeNetwork(id: "a", channel: 36, width: 20),
                makeNetwork(id: "b", channel: 40, width: 20),
            ],
            connectedBSSID: nil,
            recommendation: nil
        )

        XCTAssertEqual(layout.spans.map(\.overlapCount), [0, 0])
        XCTAssertTrue(layout.hotRegions.isEmpty)
        XCTAssertEqual(layout.maxDepth, 1)
        XCTAssertNil(layout.busiestChannel)
    }

    func testWideChannelOverlapsNeighbour() {
        let layout = RFOverviewLayout.build(
            band: .band5,
            networks: [
                makeNetwork(id: "wide", channel: 36, width: 80),
                makeNetwork(id: "narrow", channel: 40, width: 20),
            ],
            connectedBSSID: nil,
            recommendation: nil
        )

        XCTAssertEqual(layout.spans.map(\.overlapCount), [1, 1])
        XCTAssertEqual(layout.hotRegions.first?.depth, 2)
        XCTAssertEqual(layout.maxDepth, 2)
    }

    func testSpanIsClampedToTheBandDomain() {
        let layout = RFOverviewLayout.build(
            band: .band24,
            networks: [makeNetwork(id: "a", band: .band24, channel: 1, width: 40)],
            connectedBSSID: nil,
            recommendation: nil
        )

        let span = try? XCTUnwrap(layout.spans.first)
        XCTAssertEqual(span?.startMHz, RFBandGeometry.domainMHz(for: .band24).lowerBound)
        XCTAssertEqual(span?.endMHz, 2427)
    }

    func testMarkerFollowsRecommendation() {
        let recommendation = ChannelRecommendation(
            band: .band5,
            channel: 44,
            widthMHz: 80,
            score: 92,
            overlappingCount: 0,
            coChannelCount: 0,
            isDFS: false,
            rationale: "test"
        )
        let layout = RFOverviewLayout.build(
            band: .band5,
            networks: [makeNetwork(id: "a", channel: 36, width: 20)],
            connectedBSSID: nil,
            recommendation: recommendation
        )

        XCTAssertEqual(layout.marker?.channel, 44)
        XCTAssertEqual(layout.marker?.startMHz, 5180)
        XCTAssertEqual(layout.marker?.endMHz, 5260)
        XCTAssertEqual(layout.marker?.score, 92)
        XCTAssertEqual(layout.marker?.isDFS, false)
    }

    func testEmptyBandHasNoSpansMarkerOrOverlap() {
        let layout = RFOverviewLayout.build(
            band: .band24,
            networks: [makeNetwork(id: "a", band: .band5, channel: 36, width: 20)],
            connectedBSSID: nil,
            recommendation: nil
        )

        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.maxDepth, 0)
        XCTAssertNil(layout.strongestSignal)
        XCTAssertNil(layout.marker)
        XCTAssertNil(layout.busiestChannel)
        XCTAssertTrue(layout.hotRegions.isEmpty)
    }

    func testConnectedNetworkIsFlagged() {
        let layout = RFOverviewLayout.build(
            band: .band5,
            networks: [
                makeNetwork(id: "a", channel: 36, width: 20, bssid: "AA:AA:AA:AA:AA:AA"),
                makeNetwork(id: "b", channel: 44, width: 20, bssid: "BB:BB:BB:BB:BB:BB"),
            ],
            connectedBSSID: "AA:AA:AA:AA:AA:AA",
            recommendation: nil
        )

        XCTAssertEqual(layout.spans.filter(\.isConnected).map(\.id), ["a"])
        XCTAssertEqual(layout.strongestSignal, -50)
    }

    func testBusiestChannelPicksTheLargestOverlap() {
        let layout = RFOverviewLayout.build(
            band: .band24,
            networks: [
                makeNetwork(id: "a1", band: .band24, channel: 6, width: 20),
                makeNetwork(id: "a2", band: .band24, channel: 6, width: 20),
                makeNetwork(id: "a3", band: .band24, channel: 6, width: 20),
                makeNetwork(id: "b1", band: .band24, channel: 11, width: 20),
                makeNetwork(id: "b2", band: .band24, channel: 11, width: 20),
            ],
            connectedBSSID: nil,
            recommendation: nil
        )

        XCTAssertEqual(layout.busiestChannel, 6)
        XCTAssertEqual(layout.maxDepth, 3)
    }

    // MARK: - Helpers

    private func makeNetwork(
        id: String,
        band: WiFiBand = .band5,
        channel: Int,
        width: Int,
        signal: Int = -50,
        bssid: String = "00:11:22:33:44:55"
    ) -> NetworkModel {
        NetworkModel(
            id: id,
            bssid: bssid,
            ssid: "Net-\(id)",
            band: band,
            channel: channel,
            channelWidthMHz: width,
            generation: .mode11ax,
            security: "WPA2 Personal",
            vendor: "Test",
            apName: nil,
            mode: "Infrastructure",
            signal: signal,
            noise: -92,
            snr: signal + 92,
            basicRates: [6, 12, 24],
            minBasicRate: 6,
            maxBasicRate: 24,
            minRate: 6,
            maxRate: 1200,
            centerFrequency: nil,
            channelUtilization: 20,
            beaconInterval: 100,
            beaconRate: 24,
            beaconAirtime: 1,
            beaconMode: "Infrastructure",
            countryCode: "US",
            fastTransition: false,
            protectionMode: "No protection mode",
            stations: 1,
            clients: 2,
            streams: 2,
            type: "Infrastructure",
            wps: "Unknown",
            wpsEnabled: false,
            pmfRequired: false,
            ieCount: 10,
            ieTotalLength: 100,
            ratesEstimated: true,
            informationElements: [],
            count: 1,
            firstSeen: Date(timeIntervalSince1970: 0),
            lastSeen: Date(timeIntervalSince1970: 0)
        )
    }
}
