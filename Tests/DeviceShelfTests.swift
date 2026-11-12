import XCTest

final class DeviceShelfTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func scan(_ devices: [LANDevice]) -> LANScanResult {
        LANScanResult(
            interfaceName: "en0", subnet: "192.168.1.0/24", gateway: "192.168.1.1",
            devices: devices, scannedAt: now)
    }

    private func device(
        ip: String, mac: String?, vendor: String? = nil, hostname: String? = nil,
        ports: [UInt16] = [], latency: Double? = 4, gateway: Bool = false
    ) -> LANDevice {
        LANDevice(
            ip: ip, mac: mac, vendor: vendor, hostname: hostname, openPorts: ports,
            latencyMilliseconds: latency, isGateway: gateway, isThisMac: false, isNew: false)
    }

    // MARK: - Merge

    func testFirstScanCreatesDevicesWithJoinedEvent() {
        let result = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22", ports: [80])]),
            now: now)

        XCTAssertEqual(result.count, 1)
        let stored = try? XCTUnwrap(result.first)
        XCTAssertEqual(stored?.checks, 1)
        XCTAssertEqual(stored?.onlineChecks, 1)
        XCTAssertEqual(stored?.availabilityPercent, 100)
        XCTAssertEqual(stored?.isOnline, true)
        XCTAssertEqual(stored?.events.first?.kind, .joined)
    }

    func testMissingDeviceGoesOfflineAndAvailabilityDrops() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]), now: now)
        let second = DeviceShelfMerger.merge(
            first, scan: scan([device(ip: "192.168.1.30", mac: "AA:BB:CC:00:33:44")]),
            now: now.addingTimeInterval(5))

        let offline = second.first { $0.mac == "AA:BB:CC:00:11:22" }
        XCTAssertEqual(offline?.isOnline, false)
        XCTAssertEqual(offline?.checks, 2)
        XCTAssertEqual(offline?.onlineChecks, 1)
        XCTAssertEqual(offline?.availabilityPercent, 50)
        XCTAssertEqual(offline?.events.last?.kind, .left)
    }

    func testReturningDeviceGetsReturnedEvent() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]), now: now)
        // A scan that found other devices but not this one is a real "left";
        // an empty sweep is treated as no data at all.
        let second = DeviceShelfMerger.merge(
            first,
            scan: scan([device(ip: "192.168.1.30", mac: "AA:BB:CC:00:33:44")]),
            now: now.addingTimeInterval(5))
        let third = DeviceShelfMerger.merge(
            second,
            scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]),
            now: now.addingTimeInterval(10))

        let device = third.first
        XCTAssertEqual(device?.isOnline, true)
        XCTAssertEqual(device?.events.map(\.kind), [.joined, .left, .returned])
    }

    func testPortChangesAreRecorded() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22", ports: [80])]),
            now: now)
        let second = DeviceShelfMerger.merge(
            first,
            scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22", ports: [80, 22])]),
            now: now.addingTimeInterval(5))

        let event = second.first?.events.last
        XCTAssertEqual(event?.kind, .portsChanged)
        XCTAssertEqual(event?.detail, "opened 22")
    }

    func testDHCPAddressChangeKeepsTheSameShelfEntry() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]), now: now)
        let second = DeviceShelfMerger.merge(
            first,
            scan: scan([device(ip: "192.168.1.99", mac: "AA:BB:CC:00:11:22")]),
            now: now.addingTimeInterval(5))

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.ip, "192.168.1.99")
        XCTAssertEqual(second.first?.events.first?.kind, .joined)
    }

    func testEmptyScanKeepsTheShelfOnline() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]), now: now)
        let empty = DeviceShelfMerger.merge(first, scan: scan([]), now: now.addingTimeInterval(5))

        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(empty.first?.isOnline, true)
        XCTAssertEqual(empty.first?.checks, 1)
        XCTAssertEqual(empty.first?.availabilityPercent, 100)
        XCTAssertEqual(empty.first?.events.map(\.kind), [.joined])
    }

    func testBareAddressesWithoutIdentityAreNotInventoried() {
        let result = DeviceShelfMerger.merge(
            [],
            scan: scan([
                device(ip: "192.168.1.20", mac: nil, ports: []),
                device(ip: "192.168.1.1", mac: nil, ports: [], gateway: true),
                device(ip: "192.168.1.21", mac: nil, ports: [22]),
            ]),
            now: now)

        XCTAssertEqual(result.map(\.ip).sorted(), ["192.168.1.1", "192.168.1.21"])
    }

    func testLowSeverityPortsAreNotMeaningfulRisks() {
        let quiet = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22", ports: [80])]),
            now: now)[0]
        let risky = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.21", mac: "AA:BB:CC:00:11:23", ports: [23])]),
            now: now)[0]

        XCTAssertFalse(quiet.hasMeaningfulRisk)
        XCTAssertTrue(risky.hasMeaningfulRisk)
        XCTAssertFalse(quiet.riskFindings.isEmpty)
    }

    func testLatencySamplesAreCapped() {
        var devices = DeviceShelfMerger.merge(
            [], scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]), now: now)
        for _ in 0..<(DeviceShelfMerger.sampleLimit + 20) {
            devices = DeviceShelfMerger.merge(
                devices,
                scan: scan([device(ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22")]),
                now: now.addingTimeInterval(5))
        }
        XCTAssertEqual(devices.first?.latencySamples.count, DeviceShelfMerger.sampleLimit)
    }

    // MARK: - Classification

    func testClassificationUsesGatewayPortsAndNames() {
        XCTAssertEqual(
            DeviceClassifier.category(vendor: nil, hostname: nil, ports: [], isGateway: true),
            .router)
        XCTAssertEqual(
            DeviceClassifier.category(vendor: nil, hostname: nil, ports: [9100], isGateway: false),
            .printer)
        XCTAssertEqual(
            DeviceClassifier.category(vendor: nil, hostname: nil, ports: [2049], isGateway: false),
            .nas)
        XCTAssertEqual(
            DeviceClassifier.category(vendor: nil, hostname: nil, ports: [554], isGateway: false),
            .camera)
        XCTAssertEqual(
            DeviceClassifier.category(
                vendor: nil, hostname: "iPhone", ports: [], isGateway: false), .phone)
        XCTAssertEqual(
            DeviceClassifier.category(
                vendor: nil, hostname: nil, ports: [3389], isGateway: false), .computer)
        XCTAssertEqual(
            DeviceClassifier.category(vendor: nil, hostname: nil, ports: [], isGateway: false),
            .unknown)
    }

    // MARK: - Risks

    func testRiskCatalogFlagsDangerousPortsFirst() {
        let findings = DeviceRiskCatalog.findings(for: [80, 23, 445])
        XCTAssertEqual(findings.map(\.port), [23, 445, 80])
        XCTAssertEqual(findings.first?.severity, .high)
        XCTAssertEqual(DeviceRiskCatalog.score(for: findings), 100 - 35 - 15 - 5)
    }

    func testQuietDeviceScoresHundred() {
        XCTAssertEqual(DeviceRiskCatalog.score(for: []), 100)
    }
}
