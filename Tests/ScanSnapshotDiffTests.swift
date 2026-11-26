import XCTest

final class ScanSnapshotDiffTests: XCTestCase {
    private func network(
        _ bssid: String, ssid: String = "Corp", band: String = "5 GHz", channel: Int = 36,
        width: Int = 80, security: String = "WPA3 Personal", rssi: Int = -55,
        generation: String = "11ax"
    ) -> ScanSnapshotNetwork {
        ScanSnapshotNetwork(
            bssid: bssid, ssid: ssid, band: band, channel: channel, widthMHz: width,
            security: security, rssi: rssi, vendor: "Test Vendor", generation: generation)
    }

    private func snapshot(
        _ networks: [ScanSnapshotNetwork], label: String = "A",
        at date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ScanSnapshot {
        ScanSnapshot(label: label, createdAt: date, networks: networks)
    }

    func testAddedRemovedAndChangedNetworks() {
        let before = snapshot([
            network("AA:00:00:00:00:01", channel: 36),
            network("AA:00:00:00:00:02", ssid: "Guest"),
        ])
        let after = snapshot(
            [
                network("AA:00:00:00:00:01", channel: 44, width: 160),
                network("AA:00:00:00:00:03", ssid: "New"),
            ], label: "B")

        let diff = ScanSnapshotDiff.compare(before: before, after: after)
        XCTAssertEqual(diff.added.map(\.bssid), ["AA:00:00:00:00:03"])
        XCTAssertEqual(diff.removed.map(\.bssid), ["AA:00:00:00:00:02"])
        XCTAssertEqual(
            diff.changed.map { "\($0.field):\($0.from)→\($0.to)" },
            ["Channel:36→44", "Width:80→160"])
        XCTAssertEqual(diff.changeCount, 1 + 1 + 2)
        XCTAssertFalse(diff.isEmpty)
    }

    func testIdenticalScansHaveNoChanges() {
        let networks = [network("AA:00:00:00:00:01"), network("AA:00:00:00:00:02")]
        let diff = ScanSnapshotDiff.compare(
            before: snapshot(networks), after: snapshot(networks, label: "B"))
        XCTAssertTrue(diff.isEmpty)
        XCTAssertEqual(diff.changeCount, 0)
    }

    func testSmallSignalDriftIsIgnoredAndLargeShiftIsReported() {
        let before = snapshot([network("AA:00:00:00:00:01", rssi: -55)])
        let small = ScanSnapshotDiff.compare(
            before: before,
            after: snapshot([network("AA:00:00:00:00:01", rssi: -62)], label: "B"))
        XCTAssertTrue(small.isEmpty)

        let large = ScanSnapshotDiff.compare(
            before: before,
            after: snapshot([network("AA:00:00:00:00:01", rssi: -70)], label: "B"))
        XCTAssertEqual(large.changed.count, 1)
        XCTAssertEqual(large.changed.first?.field, "Signal")
        XCTAssertEqual(large.changed.first?.from, "-55 dBm")
    }

    func testSecurityChangeIsReported() {
        let before = snapshot([network("AA:00:00:00:00:01", security: "WPA3 Personal")])
        let after = snapshot(
            [network("AA:00:00:00:00:01", security: "Open")], label: "B")
        let diff = ScanSnapshotDiff.compare(before: before, after: after)
        XCTAssertEqual(diff.changed.map(\.field), ["Security"])
        XCTAssertEqual(diff.changed.first?.to, "Open")
    }

    func testCSVCarriesEveryChangeAndEscapesCommas() {
        let before = snapshot([network("AA:00:00:00:00:01", ssid: "Corp, Guest")])
        let after = snapshot(
            [
                network("AA:00:00:00:00:01", ssid: "Corp, Guest", channel: 44),
                network("AA:00:00:00:00:09", ssid: "New \"AP\""),
            ], label: "B")
        let csv = ScanSnapshotDiff.compare(before: before, after: after).csv
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(
            lines.first, "change,bssid,ssid,band,channel,width_mhz,security,rssi,field,from,to")
        XCTAssertTrue(csv.contains("\"Corp, Guest\""))
        XCTAssertTrue(csv.contains("\"New \"\"AP\"\"\""))
        XCTAssertTrue(csv.contains("changed,AA:00:00:00:00:01"))
        XCTAssertTrue(csv.contains("Channel,36,44"))
    }

    func testStoreRoundTripAndDelete() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-snapshots-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ScanSnapshotStore(url: url)
        XCTAssertTrue(store.load().isEmpty)

        let first = snapshot([network("AA:00:00:00:00:01")], label: "Before")
        let second = snapshot([network("AA:00:00:00:00:02")], label: "After")
        try store.add(first)
        try store.add(second)

        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.label), ["Before", "After"])
        XCTAssertEqual(loaded.first?.networks.first?.bssid, "AA:00:00:00:00:01")

        let remaining = try store.delete(id: first.id)
        XCTAssertEqual(remaining.map(\.label), ["After"])
    }

    func testBuilderMapsTheNetworkFields() {
        let model = makeNetwork(
            bssid: "aa:bb:cc:dd:ee:01", ssid: "Office", band: .band6, channel: 37,
            width: 160, security: "WPA3 Enterprise", vendor: "Vendor", signal: -61)
        let snapshot = ScanSnapshotBuilder.snapshot(label: "One", networks: [model])
        let row = snapshot.networks.first
        XCTAssertEqual(row?.bssid, "AA:BB:CC:DD:EE:01")
        XCTAssertEqual(row?.ssid, "Office")
        XCTAssertEqual(row?.band, WiFiBand.band6.label)
        XCTAssertEqual(row?.channel, 37)
        XCTAssertEqual(row?.widthMHz, 160)
        XCTAssertEqual(row?.security, "WPA3 Enterprise")
        XCTAssertEqual(row?.rssi, -61)
    }
}
