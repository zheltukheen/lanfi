import XCTest

@testable import LanFiCore

/// G15: device roles are inferred only from evidence LanFi actually has, and
/// the inventory baseline keeps a per-device authorization flag.
final class DeviceInventoryTests: XCTestCase {
    func testAdvertisedRoleWinsAndIsNotInferred() throws {
        let guess = try XCTUnwrap(
            DeviceRoleClassifier.guess(
                advertisedRole: "Media renderer", services: ["Printer"], openPorts: [445],
                vendor: "Synology", hostname: "nas.local"))
        XCTAssertEqual(guess.role, .mediaDevice)
        XCTAssertEqual(guess.basis, .advertised)
        XCTAssertFalse(guess.isInferred)
    }

    func testServicesThenPortsThenVendor() throws {
        let byService = try XCTUnwrap(
            DeviceRoleClassifier.guess(
                advertisedRole: nil, services: ["IPP printing"], openPorts: [], vendor: nil,
                hostname: nil))
        XCTAssertEqual(byService.role, .printer)
        XCTAssertEqual(byService.basis, .services)
        XCTAssertTrue(byService.isInferred)

        let byPort = try XCTUnwrap(
            DeviceRoleClassifier.guess(
                advertisedRole: nil, services: [], openPorts: [32400], vendor: "Unknown",
                hostname: nil))
        XCTAssertEqual(byPort.role, .mediaDevice)
        XCTAssertEqual(byPort.basis, .openPorts)

        let byVendor = try XCTUnwrap(
            DeviceRoleClassifier.guess(
                advertisedRole: nil, services: [], openPorts: [], vendor: "QNAP Systems",
                hostname: nil))
        XCTAssertEqual(byVendor.role, .storage)
        XCTAssertEqual(byVendor.basis, .vendor)
    }

    func testNoEvidenceMeansNoGuess() {
        XCTAssertNil(
            DeviceRoleClassifier.guess(
                advertisedRole: nil, services: [], openPorts: [], vendor: nil, hostname: nil))
        // A hostname that names the role is still inference, not a claim.
        let byHostname = DeviceRoleClassifier.guess(
            advertisedRole: "", services: [""], openPorts: [9999], vendor: "Acme",
            hostname: "printer-01")
        XCTAssertEqual(byHostname?.role, .printer)
        XCTAssertEqual(byHostname?.basis, .vendor)
    }

    func testFirstScanSeedsSilently() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let change = DeviceInventoryEvaluator.evaluate(
            state: .empty,
            observed: [
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas"),
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:02", name: "printer"),
            ],
            now: now)

        XCTAssertTrue(change.didSeed)
        XCTAssertTrue(change.added.isEmpty)
        XCTAssertTrue(change.unauthorized.isEmpty)
        XCTAssertEqual(change.state.entries.count, 2)
        XCTAssertEqual(change.state.seededAt, now)
        XCTAssertTrue(change.state.authorizedKeys.isEmpty)
    }

    func testSecondScanReportsNewMissingAndUnauthorizedDevices() throws {
        let seeded = Date(timeIntervalSince1970: 1_700_000_000)
        let first = DeviceInventoryEvaluator.evaluate(
            state: .empty,
            observed: [
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas"),
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:02", name: "printer"),
            ],
            now: seeded)
        var state = first.state
        state.authorize(["AA:BB:CC:DD:EE:01"])

        let second = DeviceInventoryEvaluator.evaluate(
            state: state,
            observed: [
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas.local"),
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:03", name: "camera"),
            ],
            now: seeded.addingTimeInterval(600))

        XCTAssertFalse(second.didSeed)
        XCTAssertEqual(second.added.map(\.key), ["AA:BB:CC:DD:EE:03"])
        XCTAssertEqual(second.missing.map(\.key), ["AA:BB:CC:DD:EE:02"])
        XCTAssertEqual(Set(second.unauthorized.map(\.key)), ["AA:BB:CC:DD:EE:03"])
        XCTAssertEqual(second.state.entries["AA:BB:CC:DD:EE:01"]?.name, "nas.local")
        XCTAssertEqual(second.state.entries["AA:BB:CC:DD:EE:01"]?.authorized, true)
        XCTAssertEqual(second.state.entries["AA:BB:CC:DD:EE:03"]?.authorized, false)

        state = second.state
        state.authorizeAll(now: seeded.addingTimeInterval(700))
        XCTAssertEqual(state.authorizedKeys.count, 3)
    }

    func testAuthorizationIgnoresUnknownKeysAndNeverRegresses() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = DeviceInventoryEvaluator.evaluate(
            state: .empty,
            observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas")],
            now: now
        ).state

        state.authorize(["AA:BB:CC:DD:EE:99"])
        XCTAssertEqual(state.entries.count, 1)

        state.authorize(["AA:BB:CC:DD:EE:01"])
        let authorizedAt = try XCTUnwrap(state.entries["AA:BB:CC:DD:EE:01"]?.lastSeen)

        let later = DeviceInventoryEvaluator.evaluate(
            state: state,
            observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas")],
            now: now.addingTimeInterval(3_600))
        XCTAssertTrue(later.state.entries["AA:BB:CC:DD:EE:01"]?.authorized == true)
        XCTAssertGreaterThanOrEqual(
            later.state.entries["AA:BB:CC:DD:EE:01"]?.lastSeen ?? .distantPast, authorizedAt)
        XCTAssertTrue(later.added.isEmpty)
    }

    // MARK: - Networks

    func testTrustAndMissingStayInsideTheirSubnet() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var home = DeviceInventoryEvaluator.evaluate(
            state: .empty,
            observed: [
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas"),
                LANDeviceRecord(key: "AA:BB:CC:DD:EE:02", name: "printer"),
            ],
            subnet: "192.168.1.0/24", now: now
        ).state
        home.authorize(["AA:BB:CC:DD:EE:01"], in: "192.168.1.0/24")

        // The same laptop joins a café: the café's devices are not "new" on
        // top of home's inventory, and home's devices are not "missing" here.
        let cafe = DeviceInventoryEvaluator.evaluate(
            state: home,
            observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:99", name: "router")],
            subnet: "10.20.0.0/16", now: now.addingTimeInterval(600))

        XCTAssertTrue(cafe.didSeed, "a new network seeds silently")
        XCTAssertTrue(cafe.added.isEmpty)
        XCTAssertTrue(cafe.missing.isEmpty)
        XCTAssertTrue(cafe.unauthorized.isEmpty)
        XCTAssertTrue(cafe.state.authorizedKeys(in: "10.20.0.0/16").isEmpty)
        XCTAssertTrue(
            cafe.state.authorizedKeys(in: "192.168.1.0/24").contains("AA:BB:CC:DD:EE:01"))

        // A second look at the café network now behaves like a known network.
        let cafeAgain = DeviceInventoryEvaluator.evaluate(
            state: cafe.state,
            observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:99", name: "router")],
            subnet: "10.20.0.0/16", now: now.addingTimeInterval(1_200))
        XCTAssertFalse(cafeAgain.didSeed)
        XCTAssertEqual(cafeAgain.unauthorized.map(\.key), ["AA:BB:CC:DD:EE:99"])
        XCTAssertTrue(cafeAgain.missing.isEmpty, "home devices do not belong to this network")
    }

    func testLegacyEntryIsMigratedToTheNetworkItIsSeenOn() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var legacy = DeviceInventoryState(seededAt: now.addingTimeInterval(-86_400))
        legacy.entries["AA:BB:CC:DD:EE:01"] = DeviceInventoryEntry(
            key: "AA:BB:CC:DD:EE:01", name: "nas", firstSeen: now.addingTimeInterval(-86_400),
            lastSeen: now.addingTimeInterval(-86_400), authorized: true)

        let change = DeviceInventoryEvaluator.evaluate(
            state: legacy,
            observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas.local")],
            subnet: "192.168.1.0/24", interfaceName: "en0", now: now)

        XCTAssertEqual(change.state.entries.count, 1)
        let migrated = try XCTUnwrap(change.state.entry("AA:BB:CC:DD:EE:01", in: "192.168.1.0/24"))
        XCTAssertTrue(migrated.authorized)
        XCTAssertEqual(migrated.name, "nas.local")
        XCTAssertEqual(migrated.interfaceName, "en0")
        XCTAssertEqual(migrated.firstSeen, now.addingTimeInterval(-86_400))
        XCTAssertTrue(change.added.isEmpty)
        XCTAssertTrue(change.unauthorized.isEmpty)
    }

    func testSameMACOnTwoNetworksKeepsTwoRecords() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let home = DeviceInventoryEvaluator.evaluate(
            state: .empty, observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "nas")],
            subnet: "192.168.1.0/24", now: now
        ).state
        var state = home
        state.authorizeAll(in: "192.168.1.0/24")
        state =
            DeviceInventoryEvaluator.evaluate(
                state: state,
                observed: [LANDeviceRecord(key: "AA:BB:CC:DD:EE:01", name: "guest")],
                subnet: "172.16.0.0/24", now: now.addingTimeInterval(60)
            ).state

        XCTAssertEqual(state.entries.count, 2)
        XCTAssertEqual(state.entries(in: "192.168.1.0/24").first?.name, "nas")
        XCTAssertEqual(state.entries(in: "172.16.0.0/24").first?.name, "guest")
        XCTAssertTrue(state.authorizedKeys(in: "192.168.1.0/24").contains("AA:BB:CC:DD:EE:01"))
        XCTAssertTrue(state.authorizedKeys(in: "172.16.0.0/24").isEmpty)
    }
}
