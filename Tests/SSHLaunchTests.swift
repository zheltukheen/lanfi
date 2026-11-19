import XCTest

final class SSHLaunchTests: XCTestCase {
    private func device(openPorts: [UInt16]) -> LANDevice {
        LANDevice(
            ip: "192.168.1.40", mac: "AA:BB:CC:DD:EE:01", vendor: "Apple", hostname: "nas",
            openPorts: openPorts, latencyMilliseconds: 3, isGateway: false, isThisMac: false,
            isNew: false)
    }

    func testDefaultCommandQuotesTheDestination() {
        let launch = SSHLaunchCommand(host: "192.168.1.40")
        XCTAssertEqual(launch.command, "ssh '192.168.1.40'")
        XCTAssertEqual(launch.summary, "ssh 192.168.1.40:22")
    }

    func testCustomPortAndIdentityFile() {
        let launch = SSHLaunchCommand(
            host: "sensor.local", user: "admin", port: 2222,
            identityFile: "/Users/me/.ssh/id ed25519")
        XCTAssertEqual(
            launch.command,
            "ssh -p 2222 -i '/Users/me/.ssh/id ed25519' 'admin@sensor.local'")
    }

    func testPort22IsNotSpelledOut() {
        XCTAssertEqual(
            SSHLaunchCommand(host: "host.lan", user: "me", port: 22).command,
            "ssh 'me@host.lan'")
    }

    func testSingleQuotesAreEscaped() {
        XCTAssertEqual(SSHLaunchCommand.quote("O'Brien"), "'O'\\''Brien'")
        let launch = SSHLaunchCommand(host: "host", user: "O'Brien")
        XCTAssertEqual(launch.command, "ssh 'O'\\''Brien@host'")
    }

    func testShellMetacharactersStayInsideTheQuotes() {
        let launch = SSHLaunchCommand(host: "host;rm -rf ~", user: "user")
        XCTAssertEqual(launch.command, "ssh 'user@host;rm -rf ~'")
        XCTAssertFalse(launch.isUsable)
    }

    func testUsability() {
        XCTAssertTrue(SSHLaunchCommand(host: "10.0.0.2").isUsable)
        XCTAssertFalse(SSHLaunchCommand(host: "   ").isUsable)
        XCTAssertFalse(SSHLaunchCommand(host: "two words").isUsable)
    }

    func testSensorInitCarriesUserPortAndIdentity() {
        let sensor = RemoteSensor.new(
            name: "Office", host: "office.lan", username: "admin", port: 2200,
            identityFile: "/Users/me/.ssh/office")
        let launch = SSHLaunchCommand(sensor: sensor)

        XCTAssertTrue(launch.isUsable)
        XCTAssertEqual(
            launch.command, "ssh -p 2200 -i '/Users/me/.ssh/office' 'admin@office.lan'")
    }

    func testLANDeviceNeedsPort22() {
        XCTAssertNil(SSHLaunchCommand(device: device(openPorts: [80, 443])))
        XCTAssertEqual(
            SSHLaunchCommand(device: device(openPorts: [22, 80]))?.command, "ssh '192.168.1.40'")
    }

    func testAppleScriptEscaping() {
        XCTAssertEqual(
            TerminalLauncher.appleScriptEscaped("ssh 'a\"b'\\c"),
            "ssh 'a\\\"b'\\\\c")
    }
}
