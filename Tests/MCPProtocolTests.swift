import Foundation
import XCTest

final class MCPProtocolTests: XCTestCase {
    private let expectedTools: Set<String> = [
        "lanfi_scan_summary", "lanfi_analyze", "lanfi_protocols", "lanfi_channels",
        "lanfi_capture", "lanfi_ping", "lanfi_traceroute", "lanfi_mtr", "lanfi_port_scan",
        "lanfi_path_check", "lanfi_dns", "lanfi_dns_propagation", "lanfi_whois", "lanfi_geoip",
        "lanfi_tls", "lanfi_subnet", "lanfi_interfaces", "lanfi_routes", "lanfi_lan_scan",
        "lanfi_iperf3", "lanfi_speed_test", "lanfi_uptime", "lanfi_diagnostics", "lanfi_info",
        "lanfi_spectrum",
    ]

    // MARK: - Handshake

    func testInitializeReturnsProtocolVersionAndToolsCapability() async throws {
        let response = await MCPProtocol.handle([
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [:],
        ])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, MCPProtocol.version)
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
        let server = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(server["name"] as? String, "lanfi")
    }

    func testInitializedNotificationHasNoResponse() async {
        let response = await MCPProtocol.handle([
            "jsonrpc": "2.0", "method": "notifications/initialized",
        ])
        XCTAssertNil(response)
    }

    func testUnknownMethodReturnsError() async throws {
        let response = await MCPProtocol.handle(["jsonrpc": "2.0", "id": 2, "method": "bogus"])
        let error = try XCTUnwrap(response?["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
    }

    // MARK: - Catalogue

    func testToolsListCoversEveryToolkitTool() async throws {
        let response = await MCPProtocol.handle([
            "jsonrpc": "2.0", "id": 3, "method": "tools/list",
        ])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertEqual(names, expectedTools)
        for tool in tools {
            XCTAssertNotNil(tool["description"] as? String)
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertNotNil(schema["properties"] as? [String: Any])
        }
    }

    func testUnknownToolReturnsError() async throws {
        let response = await MCPProtocol.handle([
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": ["name": "lanfi_nope", "arguments": [:]],
        ])
        let error = try XCTUnwrap(response?["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32602)
    }

    // MARK: - Scan tools

    func testAnalyzeReadsAnExportedScan() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try await callTool("lanfi_analyze", ["path": url.path])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        XCTAssertEqual(object["networkCount"] as? Int, 3)
        let networks = try XCTUnwrap(object["networks"] as? [[String: Any]])
        let names = Set(networks.compactMap { $0["ssid"] as? String })
        XCTAssertEqual(names, ["Home-5G", "Neighbour", "OpenCafe"])
        XCTAssertGreaterThan(object["averageQuality"] as? Int ?? 0, 0)
        XCTAssertFalse((object["recommendations"] as? [[String: Any]] ?? []).isEmpty)
        XCTAssertEqual(object["criticalFindings"] as? Int, 1)
    }

    func testProtocolsFilterBySSID() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try await callTool(
            "lanfi_protocols", ["path": url.path, "ssid": "Home-5G"])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        let networks = try XCTUnwrap(object["networks"] as? [[String: Any]])
        XCTAssertEqual(networks.count, 1)
        XCTAssertEqual(networks.first?["ssid"] as? String, "Home-5G")
        XCTAssertFalse((networks.first?["blocks"] as? [[String: Any]] ?? []).isEmpty)
    }

    func testChannelsReportOccupancy() async throws {
        let url = try writeFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try await callTool("lanfi_channels", ["path": url.path])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        let occupancy = try XCTUnwrap(object["occupancy"] as? [[String: Any]])
        XCTAssertTrue(occupancy.contains { $0["channel"] as? Int == 36 })
    }

    func testMissingScanFileIsAnError() async throws {
        let payload = try await callTool(
            "lanfi_scan_summary", ["path": "/nonexistent/lanfi-scan.json"])
        XCTAssertTrue(payload.isError)
        XCTAssertTrue(payload.text.contains("File not found"))
    }

    // MARK: - Probe tools without network

    func testPingRequiresAHost() async throws {
        let payload = try await callTool("lanfi_ping", [:])
        XCTAssertTrue(payload.isError)
        XCTAssertEqual(payload.text, "Pass `host`.")
    }

    func testUnsupportedDNSRecordTypeIsAnError() async throws {
        let payload = try await callTool("lanfi_dns", ["name": "example.com", "type": "NOPE"])
        XCTAssertTrue(payload.isError)
        XCTAssertTrue(payload.text.contains("Unsupported record type"))
    }

    func testSubnetCalculator() async throws {
        let payload = try await callTool("lanfi_subnet", ["input": "192.168.1.10/24"])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        XCTAssertEqual(object["network"] as? String, "192.168.1.0")
        XCTAssertEqual(object["prefixLength"] as? Int, 24)
        XCTAssertEqual(object["usableHosts"] as? Int, 254)
    }

    func testSubnetCalculatorRejectsGarbage() async throws {
        let payload = try await callTool("lanfi_subnet", ["input": "definitely not a subnet"])
        XCTAssertTrue(payload.isError)
    }

    func testSpectrumSummarisesATrace() async throws {
        // One contiguous sweep: the sweep model stores a single start/step grid.
        let csv = """
            Frequency (MHz),Amplitude (dBm)
            2400.0,-92.0
            2410.0,-84.0
            2420.0,-41.0
            2430.0,-78.0
            2440.0,-90.0
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-spectrum-\(UUID().uuidString).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let payload = try await callTool("lanfi_spectrum", ["path": url.path])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        XCTAssertEqual(object["pointCount"] as? Int, 5)
        XCTAssertEqual(object["spanMHz"] as? Double, 40.0)
        XCTAssertEqual(object["noiseFloorDbm"] as? Double, -92.0)
        let peak = try XCTUnwrap(object["peak"] as? [String: Any])
        XCTAssertEqual(peak["mhz"] as? Double, 2420.0)
        let bands = try XCTUnwrap(object["bands"] as? [[String: Any]])
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands.first?["band"] as? String, "2.4 GHz")
        XCTAssertEqual(bands.first?["peakDbm"] as? Double, -41.0)
    }

    func testSpectrumRejectsAMissingFile() async throws {
        let payload = try await callTool("lanfi_spectrum", ["path": "/tmp/lanfi-missing-spectrum.csv"])
        XCTAssertTrue(payload.isError)
    }

    func testInfoReportsTheSnapshotPath() async throws {
        let payload = try await callTool("lanfi_info", [:])
        XCTAssertFalse(payload.isError, payload.text)
        let object = try XCTUnwrap(jsonObject(payload.text))
        XCTAssertEqual(object["liveSnapshot"] as? String, MCPPaths.liveSnapshotURL.path)
    }

    // MARK: - Helpers

    private struct Payload {
        let text: String
        let isError: Bool
    }

    private func callTool(_ name: String, _ arguments: [String: Any]) async throws -> Payload {
        let response = await MCPProtocol.handle([
            "jsonrpc": "2.0", "id": 9, "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ])
        let result = try XCTUnwrap(response?["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        return Payload(text: text, isError: result["isError"] as? Bool ?? false)
    }

    private func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeFixture() throws -> URL {
        let json = """
            {"networks":[
             {"id":"aa:bb:cc:dd:ee:01","ssid":"Home-5G","bssid":"AA:BB:CC:DD:EE:01",
              "band":"5GHz","channel":36,"widthMHz":80,"generation":"Wi-Fi 6",
              "security":"WPA2/WPA3","signalDbm":-48,"noiseDbm":-92,"vendor":"Ubiquiti"},
             {"id":"aa:bb:cc:dd:ee:02","ssid":"Neighbour","bssid":"AA:BB:CC:DD:EE:02",
              "band":"5GHz","channel":36,"widthMHz":80,"generation":"Wi-Fi 5",
              "security":"WPA2","signalDbm":-72,"vendor":"TP-Link"},
             {"id":"aa:bb:cc:dd:ee:03","ssid":"OpenCafe","bssid":"AA:BB:CC:DD:EE:03",
              "band":"2.4GHz","channel":6,"widthMHz":20,"generation":"Wi-Fi 4",
              "security":"Open","signalDbm":-61,"vendor":"Cisco"}
            ]}
            """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-mcp-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url
    }
}
