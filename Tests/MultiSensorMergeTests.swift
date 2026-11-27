import LanFiCore
import XCTest

/// G3: two synthetic one-radio captures become one pcapng that LanFi's own
/// analyzer reads, with every beacon attributed to the sensor that produced it.
final class MultiSensorMergeTests: XCTestCase {
    private func capture(_ networks: [NetworkModel]) -> CaptureSource {
        let data = PcapExporter.makeCapture(networks: networks)
        let parsed = try! PcapFile.parse([UInt8](data))
        return CaptureSource(name: "sensor", capture: parsed)
    }

    func testMergedCaptureIsReadableAndKeepsBothRadios() throws {
        let networks = DemoData.networks()
        let split = max(1, networks.count / 2)
        let first = capture(Array(networks.prefix(split)))
        let second = capture(Array(networks.suffix(from: split)))
        let merged = try PcapMerge.merge([
            CaptureSource(name: "left", detail: "192.0.2.10", capture: first.capture),
            CaptureSource(name: "right", detail: "192.0.2.11", capture: second.capture),
        ])

        let beacons = try PcapAnalyzer.parse(data: Data(merged.pcapng))
        let bssids = Set(beacons.map { $0.bssid.uppercased() })
        let expected = Set(networks.map { $0.bssid.uppercased() })

        XCTAssertEqual(merged.packetCount, first.capture.packets.count + second.capture.packets.count)
        XCTAssertEqual(merged.sensorNames, ["left", "right"])
        XCTAssertFalse(beacons.isEmpty)
        XCTAssertTrue(expected.isSubset(of: bssids))
        XCTAssertEqual(beacons.count, networks.count)
    }

    func testSensorNamesAreNotLostWhenOneSourceIsEmpty() throws {
        let networks = DemoData.networks()
        let merged = try PcapMerge.merge([
            CaptureSource(name: "quiet", capture: PcapCapture(linkType: 127, packets: [])),
            capture(networks),
        ])
        XCTAssertEqual(merged.interfaceIDs["quiet"], 0)
        XCTAssertEqual(merged.interfaceIDs["sensor"], 1)
        XCTAssertEqual(merged.packetSensors.first, "sensor")
    }

    func testFileNameSanitising() {
        XCTAssertEqual(MultiSensorCaptureService.safeFileName("WLAN Pi · lobby"), "WLAN-Pi---lobby")
        XCTAssertEqual(MultiSensorCaptureService.safeFileName("../../etc/passwd"), "etc-passwd")
        XCTAssertEqual(MultiSensorCaptureService.safeFileName("///"), "sensor")
        XCTAssertEqual(MultiSensorCaptureService.safeFileName(""), "sensor")
    }
}
