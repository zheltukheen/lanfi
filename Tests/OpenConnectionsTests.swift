import XCTest

final class OpenConnectionsTests: XCTestCase {
    private let output = """
        COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Safari    12345 user    7u  IPv4 0x1234567890abcdef      0t0  TCP 192.168.1.10:52344->142.250.185.78:443 (ESTABLISHED)
        mDNSRespo  456  _mdns    8u  IPv4 0xabcdef1234567890      0t0  TCP *:5353 (LISTEN)
        ssh        789  user    3u  IPv6 0x9999999999999999      0t0  TCP [fe80::1]:22->[fe80::2]:49812 (ESTABLISHED)
        bad line
        """

    func testParsesEstablishedAndListeningRows() {
        let connections = OpenConnectionsParser.parse(output)
        XCTAssertEqual(connections.count, 3)
        let safari = connections.first { $0.process == "Safari" }
        XCTAssertEqual(safari?.pid, 12345)
        XCTAssertEqual(safari?.remoteHost, "142.250.185.78")
        XCTAssertEqual(safari?.state, "ESTABLISHED")
        XCTAssertEqual(safari?.protocolName, "IPv4")

        let listener = connections.first { $0.process == "mDNSRespo" }
        XCTAssertEqual(listener?.isListening, true)
        XCTAssertEqual(listener?.remote, "—")

        let ssh = connections.first { $0.process == "ssh" }
        XCTAssertEqual(ssh?.protocolName, "IPv6")
        XCTAssertEqual(ssh?.local.hasPrefix("[fe80::1]:22"), true)
    }

    func testGroupsByProcessAndSortsByCount() {
        let connections = OpenConnectionsParser.parse(output)
        let groups = OpenConnectionsParser.byProcess(connections)
        XCTAssertEqual(groups.map(\.count).reduce(0, +), 3)
        XCTAssertEqual(Set(groups.map(\.process)), Set(["Safari", "mDNSRespo", "ssh"]))
    }

    func testGarbageDoesNotCrash() {
        XCTAssertTrue(OpenConnectionsParser.parse("").isEmpty)
        XCTAssertTrue(OpenConnectionsParser.parse("COMMAND PID\nnonsense").isEmpty)
    }
}
