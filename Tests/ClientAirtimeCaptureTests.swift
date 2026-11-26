import XCTest

/// P1.3 — the capture accounting pass: retries and reserved airtime per client,
/// read from the 802.11 frame control and Duration/ID fields.
final class ClientAirtimeCaptureTests: XCTestCase {
    private func writeMAC(_ mac: String, at offset: Int, into frame: inout Data) {
        let bytes = mac.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        XCTAssertEqual(bytes.count, 6)
        for (index, byte) in bytes.enumerated() {
            frame[offset + index] = byte
        }
    }

    /// A ToDS data frame: address1 is the AP, address2 the client, address3 the
    /// (broadcast) destination.
    private func dataFrame(
        client: String, ap: String, duration: Int, retry: Bool
    ) -> Data {
        var frame = Data(repeating: 0, count: 24)
        frame[0] = 0x08  // data
        frame[1] = 0x01 | (retry ? 0x08 : 0)  // ToDS + optional Retry
        frame[2] = UInt8(duration & 0xFF)
        frame[3] = UInt8((duration >> 8) & 0xFF)
        writeMAC(ap, at: 4, into: &frame)
        writeMAC(client, at: 10, into: &frame)
        for index in 16..<22 { frame[index] = 0xFF }
        return frame
    }

    func testAirtimeAndRetriesAreCountedPerClient() throws {
        let client = "AA:BB:CC:00:00:01"
        let ap = "00:11:22:33:44:55"
        let packets: [(UInt32, Data, Date)] = [
            (105, dataFrame(client: client, ap: ap, duration: 1000, retry: false), Date()),
            (105, dataFrame(client: client, ap: ap, duration: 2000, retry: true), Date()),
            (105, dataFrame(client: client, ap: ap, duration: 3000, retry: false), Date()),
        ]

        let clients = PcapAnalyzer.clients(beacons: [], packets: packets)
        XCTAssertEqual(clients.count, 1)
        let entry = try XCTUnwrap(clients.first)
        XCTAssertEqual(entry.mac, client)
        XCTAssertEqual(entry.bssid, ap)
        XCTAssertEqual(entry.frameCount, 3)
        XCTAssertEqual(entry.retryFrames, 1)
        XCTAssertEqual(entry.airtimeMicroseconds, 6000)
        XCTAssertEqual(try XCTUnwrap(entry.retryRate), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testRetriesSplitAcrossClients() {
        let packets: [(UInt32, Data, Date)] = [
            (105, dataFrame(client: "AA:BB:CC:00:00:01", ap: "00:11:22:33:44:55", duration: 500, retry: true), Date()),
            (
                105, dataFrame(client: "AA:BB:CC:00:00:02", ap: "00:11:22:33:44:55", duration: 1500, retry: false),
                Date()
            ),
            (
                105, dataFrame(client: "AA:BB:CC:00:00:02", ap: "00:11:22:33:44:55", duration: 1500, retry: false),
                Date()
            ),
        ]

        let clients = PcapAnalyzer.clients(beacons: [], packets: packets)
        let first = clients.first { $0.mac == "AA:BB:CC:00:00:01" }
        let second = clients.first { $0.mac == "AA:BB:CC:00:00:02" }
        XCTAssertEqual(first?.retryFrames, 1)
        XCTAssertEqual(first?.airtimeMicroseconds, 500)
        XCTAssertEqual(second?.retryFrames, 0)
        XCTAssertEqual(second?.frameCount, 2)
        XCTAssertEqual(second?.airtimeMicroseconds, 3000)
        XCTAssertEqual(clients.first?.mac, "AA:BB:CC:00:00:02", "busiest frame count first")
    }
}
