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

// MARK: - Asset register

final class DeviceAssetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testWarrantyStatesFromOneDate() {
        XCTAssertEqual(DeviceWarranty(end: nil, now: now, calendar: calendar), .unknown)
        XCTAssertFalse(DeviceWarranty(end: nil, now: now, calendar: calendar).needsAttention)

        let in90 = calendar.date(byAdding: .day, value: 90, to: now)!
        XCTAssertEqual(DeviceWarranty(end: in90, now: now, calendar: calendar), .active(daysLeft: 90))

        let in10 = calendar.date(byAdding: .day, value: 10, to: now)!
        let expiring = DeviceWarranty(end: in10, now: now, calendar: calendar)
        XCTAssertEqual(expiring, .expiring(daysLeft: 10))
        XCTAssertTrue(expiring.needsAttention)

        XCTAssertEqual(
            DeviceWarranty(end: calendar.startOfDay(for: now), now: now, calendar: calendar),
            .expiring(daysLeft: 0))

        let ago = calendar.date(byAdding: .day, value: -5, to: now)!
        XCTAssertEqual(DeviceWarranty(end: ago, now: now, calendar: calendar), .expired(daysAgo: 5))
        XCTAssertTrue(DeviceWarranty(end: ago, now: now, calendar: calendar).needsAttention)
    }

    func testAssetTagIsOpaqueAndStableAcrossScans() {
        let first = DeviceShelfMerger.merge(
            [], scan: scan(mac: "AA:BB:CC:00:11:22"), now: now)
        let tag = first.first?.assetTag
        XCTAssertNotNil(tag)
        XCTAssertTrue(tag?.hasPrefix(DeviceShelfAsset.tagPrefix) == true)
        XCTAssertEqual(tag?.count, 11)
        XCTAssertFalse(tag!.contains("AA:BB"), "A label must not carry the MAC address")

        let second = DeviceShelfMerger.merge(first, scan: scan(mac: "AA:BB:CC:00:11:22"), now: now)
        XCTAssertEqual(second.first?.assetTag, tag)
    }

    func testLegacyShelfJSONDecodesWithoutAssetFields() throws {
        let device = try XCTUnwrap(
            DeviceShelfMerger.merge([], scan: scan(mac: "AA:BB:CC:00:11:22"), now: now).first)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(device)) as? [String: Any])
        for key in ["assetTag", "serialNumber", "purchaseDate", "warrantyEnd", "location"] {
            object.removeValue(forKey: key)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            ShelfDevice.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.assetTag)
        XCTAssertEqual(decoded.warranty, .unknown)
        XCTAssertEqual(decoded.mac, "AA:BB:CC:00:11:22")
    }

    func testWarrantyRoundTripsThroughShelfJSON() throws {
        let device = try XCTUnwrap(
            DeviceShelfMerger.merge([], scan: scan(mac: "AA:BB:CC:00:11:22"), now: now).first)
        var edited = device
        edited.serialNumber = "SN-42"
        edited.location = "Living room"
        edited.warrantyEnd = now.addingTimeInterval(86_400 * 10)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShelfDevice.self, from: encoder.encode(edited))

        XCTAssertEqual(decoded.serialNumber, "SN-42")
        XCTAssertEqual(decoded.location, "Living room")
        XCTAssertTrue(decoded.warranty.isKnown)
    }

    private func scan(mac: String) -> LANScanResult {
        LANScanResult(
            interfaceName: "en0", subnet: "192.168.1.0/24", gateway: "192.168.1.1",
            devices: [
                LANDevice(
                    ip: "192.168.1.20", mac: mac, vendor: "Test", hostname: nil, openPorts: [],
                    latencyMilliseconds: 3, isGateway: false, isThisMac: false, isNew: false)
            ],
            scannedAt: now)
    }
}

final class WakeOnLANTests: XCTestCase {
    func testMagicPacketLayout() throws {
        let packet = try XCTUnwrap(WakeOnLAN.magicPacket(mac: "AA:BB:CC:00:11:22"))
        XCTAssertEqual(packet.count, 6 + 16 * 6)
        XCTAssertEqual(Array(packet.prefix(6)), [UInt8](repeating: 0xFF, count: 6))
        let mac = Array(packet[6..<12])
        XCTAssertEqual(mac, [0xAA, 0xBB, 0xCC, 0x00, 0x11, 0x22])
        XCTAssertEqual(Array(packet.suffix(6)), mac)
    }

    func testMagicPacketAcceptsBareHexAndRejectsShortMACs() {
        XCTAssertNotNil(WakeOnLAN.magicPacket(mac: "aabbcc001122"))
        XCTAssertNil(WakeOnLAN.magicPacket(mac: "AA:BB:CC"))
    }
}

// MARK: - Labels

final class DeviceLabelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func device() throws -> ShelfDevice {
        let scan = LANScanResult(
            interfaceName: "en0", subnet: "192.168.1.0/24", gateway: "192.168.1.1",
            devices: [
                LANDevice(
                    ip: "192.168.1.20", mac: "AA:BB:CC:00:11:22", vendor: "Test",
                    hostname: "nas", openPorts: [], latencyMilliseconds: 3, isGateway: false,
                    isThisMac: false, isNew: false)
            ],
            scannedAt: now)
        var stored = try XCTUnwrap(DeviceShelfMerger.merge([], scan: scan, now: now).first)
        stored.serialNumber = "SN-42"
        stored.location = "Living room"
        return stored
    }

    func testLabelSheetIsAPDFWithOnePagePerEightLabels() throws {
        let device = try device()
        let onePage = DeviceLabelPDF.data(for: [device], generatedAt: now)
        XCTAssertEqual(String(decoding: onePage.prefix(5), as: UTF8.self), "%PDF-")

        let nine = DeviceLabelPDF.data(for: Array(repeating: device, count: 9), generatedAt: now)
        let provider = try XCTUnwrap(CGDataProvider(data: nine as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(document.numberOfPages, 2)
    }

    func testQRCodeAndPNGByte() throws {
        XCTAssertNotNil(QRCode.image(for: DeviceShelfAsset.deepLink(for: "LF-1A2B3C4D")))
        let png = try XCTUnwrap(DeviceLabelPDF.png(for: "LF-1A2B3C4D", size: 256))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
