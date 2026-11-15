import XCTest

final class ExportFormatterTests: XCTestCase {
    func testCSVUsesVisibleColumnsAndEscapesFields() {
        let columns = [
            ColumnDefinition(
                id: ColumnId.networkName.rawValue, title: "SSID", width: 120,
                isVisible: true, order: 0),
            ColumnDefinition(
                id: ColumnId.bssid.rawValue, title: "BSSID", width: 160,
                isVisible: true, order: 1),
            ColumnDefinition(
                id: ColumnId.channel.rawValue, title: "Channel", width: 60,
                isVisible: false, order: 2),
        ]
        let exporter = ScanCSVExporter(
            columns: columns,
            formatter: NetworkColumnFormatter(
                signalDisplayMode: .dbm, connectedBSSID: nil,
                metricsByNetworkId: [:], annotationsByNetworkId: [:]),
            expressions: [],
            metrics: [:]
        )
        let network = makeNetwork(
            bssid: "AA:BB:CC:DD:EE:01", ssid: "Cafe \"Guest\"")

        let csv = exporter.make(networks: [network])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}\"SSID\",\"BSSID\"\r\n"))
        XCTAssertTrue(csv.contains("\"Cafe \"\"Guest\"\"\""))
        XCTAssertFalse(csv.contains("Channel"))
    }

    func testJSONPayloadHasSummaryNetworksAndRecommendations() throws {
        let network = makeNetwork(ssid: "Office", band: .band5, channel: 36)
        let analysis = NetworkAnalyzer.analyze(networks: [network])
        let exporter = ScanJSONExporter(version: "5.3.0", analysis: analysis)

        let payload = exporter.make(networks: [network])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertEqual(payload["generator"] as? String, "LanFi")
        XCTAssertEqual(payload["version"] as? String, "5.3.0")
        let summary = payload["summary"] as? [String: Any]
        XCTAssertEqual(summary?["networks"] as? Int, 1)
        let networks = payload["networks"] as? [[String: Any]]
        XCTAssertEqual(networks?.first?["ssid"] as? String, "Office")
        XCTAssertNotNil(payload["recommendations"])
    }
}
