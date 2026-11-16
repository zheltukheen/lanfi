import XCTest

final class CoLocatedAPTests: XCTestCase {
    private func element(id: Int, name: String, length: Int, detail: String) -> InformationElement {
        InformationElement(
            id: "\(id)", elementId: id, length: length, name: name, summary: detail,
            detailLines: [detail], rawHex: "")
    }

    private func network(
        bssid: String,
        band: WiFiBand,
        channel: Int,
        apName: String? = nil,
        vendor: String = "Netgear",
        model: String? = "R7800",
        extraElementLength: Int = 12
    ) -> NetworkModel {
        var elements: [InformationElement] = [
            element(id: 0, name: "SSID", length: 0, detail: ""),
            element(id: 1, name: "Supported Rates", length: 8, detail: "Rates"),
            element(id: 3, name: "DS Parameter Set", length: 1, detail: "Current channel: \(channel)"),
            element(id: 45, name: "HT Capabilities", length: extraElementLength, detail: "HT"),
        ]
        if let model {
            elements.append(element(id: 221, name: "Vendor Specific", length: 24, detail: "Model: \(model)"))
        }
        return NetworkModel(
            id: bssid, bssid: bssid, ssid: "Home", band: band, channel: channel,
            channelWidthMHz: 80, generation: .mode11ax, security: "WPA2",
            vendor: vendor, apName: apName, mode: "Infrastructure", signal: -55,
            noise: nil, snr: nil, basicRates: nil, minBasicRate: nil,
            maxBasicRate: nil, minRate: nil, maxRate: nil, centerFrequency: nil,
            channelUtilization: nil, beaconInterval: nil, beaconRate: nil,
            beaconAirtime: nil, beaconMode: nil, countryCode: nil,
            fastTransition: nil, protectionMode: nil, stations: nil, clients: nil,
            streams: nil, type: nil, wps: nil, wpsEnabled: nil, pmfRequired: nil,
            ieCount: elements.count, ieTotalLength: nil, ratesEstimated: false,
            informationElements: elements, count: 1, firstSeen: Date(), lastSeen: Date())
    }

    func testUnnamedRadiosOnDifferentBandsMerge() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band24, channel: 6),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 36),
        ]
        let keys = CoLocatedAPDetector.groupKeys(for: networks)
        XCTAssertEqual(keys["AA:BB:CC:00:00:01"], keys["AA:BB:CC:00:00:02"])
    }

    func testSameBandDuplicatesStaySeparate() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band5, channel: 36),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 149),
        ]
        let keys = CoLocatedAPDetector.groupKeys(for: networks)
        XCTAssertNotEqual(keys["AA:BB:CC:00:00:01"], keys["AA:BB:CC:00:00:02"])
    }

    func testDifferentModelsStaySeparate() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band24, channel: 6, model: "R7800"),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 36, model: "R8000"),
        ]
        let keys = CoLocatedAPDetector.groupKeys(for: networks)
        XCTAssertNotEqual(keys["AA:BB:CC:00:00:01"], keys["AA:BB:CC:00:00:02"])
    }

    func testMissingModelFallsBackToBSSID() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band24, channel: 6, model: nil),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 36, model: nil),
        ]
        let keys = CoLocatedAPDetector.groupKeys(for: networks)
        XCTAssertNotEqual(keys["AA:BB:CC:00:00:01"], keys["AA:BB:CC:00:00:02"])
    }

    func testAdvertisedNameWinsOverFingerprint() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band5, channel: 36, apName: "Lobby"),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 149, apName: "Lobby"),
        ]
        let keys = CoLocatedAPDetector.groupKeys(for: networks)
        XCTAssertEqual(keys["AA:BB:CC:00:00:01"], keys["AA:BB:CC:00:00:02"])
    }

    func testCoLocatedSiblingsListsTheOtherRadiosOfTheSameAP() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band24, channel: 6),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 36),
            network(bssid: "AA:BB:CC:00:00:03", band: .band5, channel: 149, model: "R8000"),
        ]
        let siblings = CoLocatedAPDetector.coLocatedSiblings(
            of: networks[0], in: networks)
        XCTAssertEqual(siblings.map(\.bssid), ["AA:BB:CC:00:00:02"])
        // Named radios are grouped by name, not by the fingerprint heuristic.
        let named = network(bssid: "AA:BB:CC:00:00:04", band: .band5, channel: 36, apName: "Lobby")
        XCTAssertTrue(
            CoLocatedAPDetector.coLocatedSiblings(of: named, in: [named]).isEmpty)
    }

    func testGroupingCollapsesCoLocatedRadiosIntoOneGroup() {
        let networks = [
            network(bssid: "AA:BB:CC:00:00:01", band: .band24, channel: 6),
            network(bssid: "AA:BB:CC:00:00:02", band: .band5, channel: 36),
        ]
        let rows = NetworkGrouper.rows(
            for: networks, mode: .physicalAP, metricsByNetworkId: [:],
            annotationsByNetworkId: [:])
        let groups = rows.compactMap { row -> NetworkGroup? in
            if case .group(let group) = row { return group }
            return nil
        }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.networkCount, 2)
    }
}
