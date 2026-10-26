import XCTest

final class RemoteSensorTests: XCTestCase {
    func testSSHArgumentsRejectOptionInjection() throws {
        let sensor = RemoteSensor.new(name: "Bad", host: "-oProxyCommand=evil", username: "root")
        XCTAssertThrowsError(try RemoteSensorService.sshArguments(for: sensor))
    }

    func testSSHArgumentsIncludeIdentityAndPort() throws {
        let sensor = RemoteSensor.new(
            name: "Lab", host: "10.0.0.5", username: "sensor", port: 2222,
            identityFile: "/Users/me/.ssh/id_ed25519"
        )
        let args = try RemoteSensorService.sshArguments(for: sensor)
        XCTAssertTrue(args.contains("2222"))
        XCTAssertTrue(args.contains("/Users/me/.ssh/id_ed25519"))
        XCTAssertTrue(args.contains("sensor@10.0.0.5"))
    }

    func testParsesSPAirPortJSON() throws {
        let json = """
            {"SPAirPortDataType":[{"spairport_airport_interfaces":[{
              "spairport_airport_other_local_wireless_networks":[
                {"_name":"Lab-5G","spairport_network_channel":"36 (5GHz, 160MHz)",
                 "spairport_network_phymode":"802.11ax","spairport_signal_noise":"-51 dBm / -85 dBm",
                 "spairport_security_mode":"spairport_security_mode_wpa3_personal"},
                {"_name":"Lab-2G","spairport_network_channel":"6 (2GHz, 20MHz)",
                 "spairport_network_phymode":"802.11n","spairport_signal_noise":"-66 dBm / -90 dBm",
                 "spairport_security_mode":"spairport_security_mode_wpa2_personal"}
              ]
            }]}]}
            """
        let networks = try RemoteSensorService.parse(Data(json.utf8))
        XCTAssertEqual(networks.count, 2)
        XCTAssertEqual(networks[0].ssid, "Lab-5G")
        XCTAssertEqual(networks[0].channel, 36)
        XCTAssertEqual(networks[0].widthMHz, 160)
        XCTAssertEqual(networks[0].rssi, -51)
        XCTAssertEqual(networks[0].snr, 34)
        XCTAssertEqual(networks[1].band, "2.4 GHz")
    }

    func testRejectsNonSPAirPortJSON() {
        XCTAssertThrowsError(try RemoteSensorService.parse(Data("{}".utf8)))
    }
}
