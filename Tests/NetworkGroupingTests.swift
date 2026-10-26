import XCTest

final class NetworkGroupingTests: XCTestCase {
    func testNoneModeReturnsOnlyNetworks() {
        let networks = [makeNetwork(id: "a"), makeNetwork(id: "b")]
        let rows = NetworkGrouper.rows(for: networks, mode: .none, metricsByNetworkId: [:], annotationsByNetworkId: [:])
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { $0.network != nil })
    }

    func testSSIDGroupingPutsHeadersBeforeMembers() {
        let networks = [
            makeNetwork(id: "a", ssid: "Office"),
            makeNetwork(id: "b", ssid: "Office"),
            makeNetwork(id: "c", ssid: "Guest"),
        ]
        let rows = NetworkGrouper.rows(for: networks, mode: .ssid, metricsByNetworkId: [:], annotationsByNetworkId: [:])

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.filter { $0.network == nil }.count, 2)
        let groups = rows.compactMap { row -> NetworkGroup? in
            if case .group(let group) = row { return group }
            return nil
        }
        XCTAssertEqual(groups.map(\.value), ["Guest", "Office"])
        XCTAssertEqual(groups.first(where: { $0.value == "Office" })?.networkCount, 2)
        XCTAssertTrue(groups.first(where: { $0.value == "Office" })?.subtitle.contains("best") == true)
    }

    func testBandAndVendorGrouping() {
        let networks = [
            makeNetwork(id: "a", band: .band24, vendor: "Acme"),
            makeNetwork(id: "b", band: .band5, vendor: "Acme"),
            makeNetwork(id: "c", band: .band5, vendor: "-"),
        ]
        let bands = NetworkGrouper.rows(
            for: networks, mode: .band, metricsByNetworkId: [:], annotationsByNetworkId: [:])
        XCTAssertEqual(bands.compactMap { $0.network == nil ? nil : 1 }.count, 3)

        let vendors = NetworkGrouper.rows(
            for: networks, mode: .vendor, metricsByNetworkId: [:], annotationsByNetworkId: [:])
        let groupTitles = vendors.compactMap { row -> String? in
            if case .group(let group) = row { return group.value }
            return nil
        }
        XCTAssertTrue(groupTitles.contains("Acme"))
        XCTAssertTrue(groupTitles.contains("Unknown vendor"))
    }

    func testGroupAverageQualityUsesMetrics() {
        let first = makeNetwork(id: "a", ssid: "Same", signal: -50)
        let second = makeNetwork(id: "b", ssid: "Same", signal: -80)
        let report = NetworkAnalyzer.analyze(networks: [first, second])
        let rows = NetworkGrouper.rows(
            for: [first, second],
            mode: .ssid,
            metricsByNetworkId: report.metricsByNetworkId,
            annotationsByNetworkId: [:]
        )
        let group = try? XCTUnwrap(
            rows.compactMap { row -> NetworkGroup? in
                if case .group(let group) = row { return group }
                return nil
            }.first)
        XCTAssertNotNil(group?.averageQuality)
        XCTAssertEqual(group?.networkCount, 2)
    }
}
