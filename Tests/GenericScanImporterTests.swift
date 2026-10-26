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
