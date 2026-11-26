import XCTest

@testable import LanFiCore

/// The change-detection values moved out of the app target. These tests run
/// with `swift test` and need no CoreWLAN, AppKit or running app.
final class ChangeDetectionCoreTests: XCTestCase {
    private func network(
        _ bssid: String, ssid: String = "Corp", channel: Int = 36, rssi: Int = -55
    ) -> ScanSnapshotNetwork {
        ScanSnapshotNetwork(
            bssid: bssid, ssid: ssid, band: "5GHz", channel: channel, widthMHz: 80,
            security: "WPA3", rssi: rssi, vendor: "Acme", generation: "11ax")
    }

    func testSnapshotDiffFindsAddedRemovedAndChanged() {
        let before = ScanSnapshot(
            label: "A", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            networks: [network("AA:00:00:00:00:01"), network("AA:00:00:00:00:02")])
        let after = ScanSnapshot(
            label: "B", createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            networks: [network("AA:00:00:00:00:01", channel: 44), network("AA:00:00:00:00:03")])

        let diff = ScanSnapshotDiff.compare(before: before, after: after)
        XCTAssertEqual(diff.added.map(\.bssid), ["AA:00:00:00:00:03"])
        XCTAssertEqual(diff.removed.map(\.bssid), ["AA:00:00:00:00:02"])
        XCTAssertEqual(diff.changed.map(\.field), ["Channel"])
        XCTAssertTrue(diff.csv.contains("changed,AA:00:00:00:00:01"))
    }

    func testSnapshotStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-core-snapshots-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ScanSnapshotStore(url: url)
        let snapshot = ScanSnapshot(label: "One", networks: [network("AA:00:00:00:00:01")])

        try store.add(snapshot)
        XCTAssertEqual(store.load().map(\.label), ["One"])
        XCTAssertEqual(try store.delete(id: snapshot.id).count, 0)
    }

    func testBaselineStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-core-baseline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = NetworkBaselineStore(url: url)
        XCTAssertEqual(store.load(), .empty)

        let entry = NetworkBaselineEntry(
            bssid: "AA:00:00:00:00:01", ssid: "Corp", vendor: "Acme", channel: 36,
            signal: -60, firstSeen: Date(timeIntervalSince1970: 1_700_000_000))
        var state = NetworkBaselineState(seededAt: Date(timeIntervalSince1970: 1_700_000_000))
        state.baseline[entry.bssid] = entry
        state.pending[entry.bssid] = entry
        try store.save(state)

        let loaded = store.load()
        XCTAssertEqual(loaded.baseline.count, 1)
        XCTAssertEqual(loaded.pending.values.first?.bssid, entry.bssid)
    }

    func testRequirementIsOffByDefaultAndSummarises() {
        XCTAssertFalse(SurveyRequirement.off.isEnabled)
        XCTAssertFalse(SurveyRequirement.off.judgesThroughput)

        let requirement = SurveyRequirement(
            isEnabled: true, minRSSI: -67, minThroughputMbps: 50,
            maxLatencyMilliseconds: 60)
        XCTAssertTrue(requirement.summary.contains("-67"))
        XCTAssertTrue(requirement.summary.contains("50"))
        XCTAssertTrue(requirement.summary.contains("60"))
    }

    func testChannelAirtimeShareIsDerivedByTheCaller() {
        var entry = ChannelAirtimeEntry(
            bssid: "AA:00:00:00:00:01", ssid: "Corp", frames: 2, airtimeMicroseconds: 4_000,
            dataFrames: 2)
        XCTAssertFalse(entry.isLegacy)
        XCTAssertEqual(entry.airtimeMilliseconds, 4)

        entry.legacyFrames = 1
        entry.share = 0.8
        XCTAssertTrue(entry.isLegacy)
        XCTAssertEqual(entry.share, 0.8)
    }
}
