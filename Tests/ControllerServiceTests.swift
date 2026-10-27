import XCTest

final class SNMPControllerTests: XCTestCase {
    func testParsesWalkOutput() {
        let rows = SNMPController.parse("1.3.6.1.2.1.1.1.0 = Test AP\n1.3.6.1.2.1.1.5.0 = Lab")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.name, "Test AP")
    }
}

final class ControllerTelemetryTests: XCTestCase {
    func testUniFiRadioTelemetry() throws {
        let json = """
            {"data":[{"_id":"ap1","name":"Office","mac":"AA:BB:CC:DD:EE:FF","model":"U6","ip":"192.0.2.5","num_sta":7,"radio_table_stats":[{"channel":36,"tx_power":20,"cu_total":44}]}]}
            """
        let aps = try ControllerService.parse(Data(json.utf8), kind: .unifi)
        XCTAssertEqual(aps.first?.channel, 36)
        XCTAssertEqual(aps.first?.clients, 7)
        XCTAssertEqual(aps.first?.utilization, 44)
    }
}
