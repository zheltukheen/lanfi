import XCTest

final class GenericScanImporterTests: XCTestCase {
    func testParsesCSV() {
        let text = """
            ssid,bssid,band,channel,widthMHz,signal,security,vendor
            Lab,AA:BB:CC:DD:EE:FF,5GHz,36,80,-52,WPA3 Personal,Test
            """
        let networks = GenericScanImporter.parseCSV(text)
        XCTAssertEqual(networks.count, 1)
        XCTAssertEqual(networks[0].ssid, "Lab")
        XCTAssertEqual(networks[0].channel, 36)
        XCTAssertEqual(networks[0].signal, -52)
        XCTAssertEqual(networks[0].band, .band5)
    }

    func testParsesJSONNetworks() throws {
        let json = """
            {"networks":[{"ssid":"Lab","bssid":"AA:BB:CC:DD:EE:FF","band":"2.4GHz","channel":6,"signalDbm":-60,"security":"WPA2"}]}
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "lanfi-import-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let networks = try GenericScanImporter.load(url)
        XCTAssertEqual(networks.first?.band, .band24)
        XCTAssertEqual(networks.first?.channel, 6)
    }
}

final class GenericScanImporterAliasTests: XCTestCase {
    func testMapsForeignColumnsAndReportsTheRest() {
        let text = """
            Network Name,BSSID,Frequency,Signal,Channel Width,Security,First Seen,Last Seen
            Lab,AA:BB:CC:DD:EE:FF,5180,-52 dBm,80 MHz,WPA3 Personal,10:00,10:05
            """
        let result = GenericScanImporter.parseCSVDetailed(text)
        XCTAssertEqual(result.networks.count, 1)
        XCTAssertEqual(result.networks.first?.ssid, "Lab")
        XCTAssertEqual(result.networks.first?.channel, 36)
        XCTAssertEqual(result.networks.first?.band, .band5)
        XCTAssertEqual(result.networks.first?.channelWidthMHz, 80)
        XCTAssertEqual(result.networks.first?.signal, -52)
        XCTAssertEqual(result.unmappedColumns, ["First Seen", "Last Seen"])
    }

    func testDerives24GHzChannelFromFrequencyAndUnderscoredHeaders() {
        let text = """
            network_name,bssid,frequency_mhz,rssi_db,channel_width
            Guest,AA:BB:CC:DD:EE:01,2412,-67,20
            """
        let result = GenericScanImporter.parseCSVDetailed(text)
        XCTAssertEqual(result.networks.first?.band, .band24)
        XCTAssertEqual(result.networks.first?.channel, 1)
        XCTAssertEqual(result.networks.first?.signal, -67)
        XCTAssertEqual(result.unmappedColumns, [])
    }

    func testEmptyHeaderAliasesAreNotReportedAsUnmapped() {
        let text = "ssid,bssid,,signal\nLab,AA:BB:CC:DD:EE:02,-60"
        let result = GenericScanImporter.parseCSVDetailed(text)
        XCTAssertEqual(result.networks.count, 1)
        XCTAssertEqual(result.unmappedColumns, [])
    }

    func testCSVWithoutIdentityReportsItsHeaders() {
        let result = GenericScanImporter.parseCSVDetailed("when,where\n1,2")
        XCTAssertTrue(result.networks.isEmpty)
        XCTAssertEqual(result.unmappedColumns, ["when", "where"])
    }

    func testJSONRowReportsUnknownKeys() throws {
        let json = """
            {"networks":[{"ssid":"Lab","bssid":"AA:BB:CC:DD:EE:03","frequency":5955,"rssi":-50,"noise":-95}]}
            """
        let result = try GenericScanImporter.loadDetailed(
            data: Data(json.utf8), filename: "scan.json")
        XCTAssertEqual(result.networks.first?.band, .band6)
        XCTAssertEqual(result.networks.first?.channel, 1)
        XCTAssertEqual(result.unmappedColumns, ["noise"])
    }
}

final class GenericScanImporterDataTests: XCTestCase {
    func testLoadsCSVFromData() throws {
        let text =
            "ssid,bssid,band,channel,widthMHz,signal,security,vendor\nLab,AA:BB:CC:DD:EE:11,6GHz,37,320,-48,WPA3,Test"
        let networks = try GenericScanImporter.load(data: Data(text.utf8), filename: "scan.csv")
        XCTAssertEqual(networks.first?.band, .band6)
        XCTAssertEqual(networks.first?.channelWidthMHz, 320)
    }
}
