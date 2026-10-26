import XCTest

final class ColumnCatalogTests: XCTestCase {

    func testEveryDeclaredColumnAppearsExactlyOnceInDisplayOrder() {
        XCTAssertEqual(ColumnId.displayOrder.count, ColumnId.allCases.count)
        XCTAssertEqual(Set(ColumnId.displayOrder), Set(ColumnId.allCases))
        XCTAssertEqual(ColumnId.displayOrder.count, Set(ColumnId.displayOrder).count)
        XCTAssertEqual(ColumnDefinition.defaults.count, ColumnId.allCases.count)
        XCTAssertEqual(Set(ColumnDefinition.defaults.map(\.id)).count, ColumnId.allCases.count)
    }

    func testEveryColumnHasUsableMetadata() {
        for column in ColumnId.allCases {
            XCTAssertFalse(column.defaultTitle.isEmpty, "Missing title for \(column.rawValue)")
            XCTAssertGreaterThan(column.defaultWidth, 0, "Invalid width for \(column.rawValue)")
            XCTAssertNotNil(ColumnId(rawValue: column.rawValue))
        }
    }

    func testAllColumnsRenderForFullyPopulatedNetwork() {
        let network = makeNetwork(
            id: "full",
            bssid: "00:1A:2B:11:22:33",
            ssid: "Full Fixture",
            band: .band6,
            channel: 37,
            width: 160,
            generation: .mode11be,
            security: "WPA3 Personal",
            signal: -55,
            noise: -95,
            snr: 40,
            utilization: 23,
            centerFrequency: 6135,
            clients: 7,
            stations: 8,
            wpsEnabled: true,
            pmfRequired: true
        )
        let report = NetworkAnalyzer.analyze(networks: [network])
        let formatter = NetworkColumnFormatter(
            signalDisplayMode: .dbm,
            connectedBSSID: network.bssid,
            metricsByNetworkId: report.metricsByNetworkId
        )

        for column in ColumnId.allCases {
            let value = formatter.text(for: column, network: network)
            XCTAssertFalse(value.isEmpty, "Empty value for \(column.rawValue)")
            XCTAssertFalse(value.contains("Optional("), "Unwrapped optional leaked into \(column.rawValue)")
            XCTAssertNotEqual(value, "-", "Fixture should populate \(column.rawValue)")
            XCTAssertFalse(value.contains("\n"), "Newline in \(column.rawValue)")
        }
    }

    func testAllColumnsRenderForMinimalNetworkWithoutCrashing() {
        let network = makeNetwork(
            id: "minimal",
            bssid: "",
            ssid: "",
            band: .unknown,
            channel: 0,
            width: 0,
            generation: .unknown,
            security: "Unknown",
            signal: -100,
            noise: nil,
            snr: nil,
            utilization: nil,
            centerFrequency: nil,
            clients: nil,
            stations: nil,
            wpsEnabled: nil,
            pmfRequired: nil
        )
        let formatter = NetworkColumnFormatter(
            signalDisplayMode: .percent,
            connectedBSSID: nil,
            metricsByNetworkId: [:]
        )

        for column in ColumnId.allCases {
            let value = formatter.text(for: column, network: network)
            XCTAssertFalse(value.isEmpty, "Empty value for \(column.rawValue)")
            XCTAssertFalse(value.contains("Optional("), "Unwrapped optional leaked into \(column.rawValue)")
        }
    }

    func testEveryColumnSortComparatorIsConsistent() {
        let first = makeNetwork(
            id: "a", bssid: "00:11:22:33:44:55", ssid: "Alpha", band: .band24, channel: 1,
            width: 20, generation: .mode11n, security: "WPA2 Personal", signal: -70,
            noise: -90, snr: 20, utilization: 60, centerFrequency: 2412, clients: 2,
            stations: 3, wpsEnabled: false, pmfRequired: false
        )
        let second = makeNetwork(
            id: "b", bssid: "66:77:88:99:AA:BB", ssid: "Beta", band: .band5, channel: 149,
            width: 80, generation: .mode11ax, security: "WPA3 Personal", signal: -45,
            noise: -95, snr: 50, utilization: 10, centerFrequency: 5745, clients: 9,
            stations: 10, wpsEnabled: true, pmfRequired: true
        )
        let report = NetworkAnalyzer.analyze(networks: [first, second])
        let formatter = NetworkColumnFormatter(
            signalDisplayMode: .dbm,
            connectedBSSID: first.bssid,
            metricsByNetworkId: report.metricsByNetworkId
        )

        for column in ColumnId.allCases {
            XCTAssertFalse(formatter.compare(first, first, by: column), "Self-comparison failed for \(column.rawValue)")
            let forward = formatter.compare(first, second, by: column)
            let backward = formatter.compare(second, first, by: column)
            XCTAssertFalse(forward && backward, "Comparator is not antisymmetric for \(column.rawValue)")
        }
    }

    func testSignalDisplayModesFormatBothUnits() {
        XCTAssertEqual(NetworkColumnFormatter.formatSignal(-70, mode: .dbm), "-70")
        XCTAssertEqual(NetworkColumnFormatter.formatSignal(-70, mode: .percent), "60%")
        XCTAssertEqual(NetworkColumnFormatter.formatSignal(-120, mode: .percent), "0%")
        XCTAssertEqual(NetworkColumnFormatter.formatSignal(-20, mode: .percent), "100%")
    }
}
