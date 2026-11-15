import XCTest

final class MonitorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testFirstConnectionEmitsConnectedAndSample() {
        var snapshot = MonitorSnapshot()
        let network = makeNetwork(id: "a", bssid: "AA:BB:CC:DD:EE:01", ssid: "Office", signal: -55)

        XCTAssertTrue(snapshot.ingest(connected: network, now: start, sampleInterval: 60))
        XCTAssertEqual(snapshot.samples.count, 1)
        XCTAssertEqual(snapshot.samples.first?.rssi, -55)
        XCTAssertEqual(snapshot.events.map(\.kind), [.connected])
        XCTAssertEqual(snapshot.state?.bssid, "AA:BB:CC:DD:EE:01")
    }

    func testSampleIsThrottledButStateStillUpdates() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(connected: makeNetwork(id: "a", signal: -55), now: start, sampleInterval: 60)

        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -65),
            now: start.addingTimeInterval(10), sampleInterval: 60)
        XCTAssertEqual(snapshot.samples.count, 1)
        XCTAssertEqual(snapshot.state?.rssi, -65)

        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -70),
            now: start.addingTimeInterval(61), sampleInterval: 60)
        XCTAssertEqual(snapshot.samples.count, 2)
        XCTAssertEqual(snapshot.samples.last?.rssi, -70)
    }

    func testRoamingEmitsBSSIDChange() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", bssid: "AA:BB:CC:DD:EE:01", ssid: "Office"),
            now: start, sampleInterval: 0
        )
        snapshot.ingest(
            connected: makeNetwork(id: "b", bssid: "AA:BB:CC:DD:EE:02", ssid: "Office"),
            now: start.addingTimeInterval(5), sampleInterval: 0
        )

        XCTAssertTrue(snapshot.events.contains { $0.kind == .roamed })
        XCTAssertEqual(snapshot.state?.bssid, "AA:BB:CC:DD:EE:02")
        XCTAssertEqual(snapshot.samples.count, 2)
    }

    func testRoamToWeakerLinkEmitsRoamingFailure() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", bssid: "AA:BB:CC:DD:EE:01", signal: -55),
            now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "b", bssid: "AA:BB:CC:DD:EE:02", signal: -82),
            now: start.addingTimeInterval(5), sampleInterval: 0)

        XCTAssertTrue(snapshot.events.contains { $0.kind == .roamed })
        XCTAssertTrue(snapshot.events.contains { $0.kind == .roamingFailure })
    }

    func testRoamToStrongerLinkDoesNotEmitRoamingFailure() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", bssid: "AA:BB:CC:DD:EE:01", signal: -70),
            now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "b", bssid: "AA:BB:CC:DD:EE:02", signal: -50),
            now: start.addingTimeInterval(5), sampleInterval: 0)

        XCTAssertFalse(snapshot.events.contains { $0.kind == .roamingFailure })
    }

    func testChannelChangeEmitsEvent() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", channel: 6), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", channel: 36), now: start.addingTimeInterval(5), sampleInterval: 0)

        XCTAssertEqual(snapshot.events.map(\.kind), [.connected, .channelChanged])
    }

    func testSecurityDowngradeEmitsEvent() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", security: "WPA3 Personal"), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", security: "Open"), now: start.addingTimeInterval(5), sampleInterval: 0)

        XCTAssertTrue(snapshot.events.contains { $0.kind == .securityChanged })
        XCTAssertEqual(snapshot.state?.security, "Open")
    }

    func testWeakSignalCrossingEmitsOnlyOnCross() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(connected: makeNetwork(id: "a", signal: -60), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -80), now: start.addingTimeInterval(5), sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -76), now: start.addingTimeInterval(10), sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -82), now: start.addingTimeInterval(15), sampleInterval: 0)

        XCTAssertEqual(snapshot.events.filter { $0.kind == .weakSignal }.count, 1)
    }

    func testDisconnectEmitsOnceAndClearsState() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(connected: makeNetwork(id: "a"), now: start, sampleInterval: 0)

        XCTAssertTrue(snapshot.ingest(connected: nil, now: start.addingTimeInterval(5), sampleInterval: 0))
        XCTAssertEqual(snapshot.events.last?.kind, .disconnected)
        XCTAssertNil(snapshot.state)

        XCTAssertFalse(snapshot.ingest(connected: nil, now: start.addingTimeInterval(10), sampleInterval: 0))
        XCTAssertEqual(snapshot.events.filter { $0.kind == .disconnected }.count, 1)
    }

    func testVisibleNetworksBuildPeerAggregates() {
        var snapshot = MonitorSnapshot()
        let first = makeNetwork(id: "a", bssid: "AA:BB:CC:DD:EE:01", signal: -50)
        let second = makeNetwork(id: "b", bssid: "AA:BB:CC:DD:EE:02", signal: -70)

        snapshot.ingest(
            connected: first, visible: [first, second], now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: first, visible: [first, second], now: start.addingTimeInterval(5),
            sampleInterval: 0)

        XCTAssertEqual(snapshot.peers.count, 2)
        let peer = snapshot.peers["a"]
        XCTAssertEqual(peer?.samples, 2)
        XCTAssertEqual(peer?.rssiMin, -50)
        XCTAssertEqual(peer?.rssiMax, -50)
        XCTAssertEqual(peer?.averageRSSI, -50)
        XCTAssertEqual(snapshot.peers["b"]?.averageRSSI, -70)
    }

    func testPMFLossEmitsSecurityEvent() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", pmfRequired: true), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", pmfRequired: false),
            now: start.addingTimeInterval(5), sampleInterval: 0)

        let event = snapshot.events.last
        XCTAssertEqual(event?.kind, .securityChanged)
        XCTAssertTrue(event?.detail.contains("PMF") == true)
    }

    func testWPSEnabledEmitsSecurityEvent() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(
            connected: makeNetwork(id: "a", wpsEnabled: false), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", wpsEnabled: true),
            now: start.addingTimeInterval(5), sampleInterval: 0)

        let event = snapshot.events.last
        XCTAssertEqual(event?.kind, .securityChanged)
        XCTAssertTrue(event?.detail.contains("WPS") == true)
    }

    func testComparisonComparesCurrentAndPreviousWindows() {
        let now = start.addingTimeInterval(3_600)
        let current = MonitorSample(
            network: makeNetwork(id: "a", signal: -50), at: now.addingTimeInterval(-60))
        let previous = MonitorSample(
            network: makeNetwork(id: "a", signal: -70), at: now.addingTimeInterval(-3_600 - 60))

        let comparison = MonitorComparison(
            samples: [current, previous], window: 3_600, now: now)

        XCTAssertEqual(comparison.currentAverage, -50)
        XCTAssertEqual(comparison.previousAverage, -70)
        XCTAssertEqual(comparison.currentSamples, 1)
        XCTAssertEqual(comparison.previousSamples, 1)
        XCTAssertEqual(comparison.delta, 20)
    }

    func testComparisonWithoutPreviousWindowHasNoDelta() {
        let now = start
        let sample = MonitorSample(network: makeNetwork(id: "a", signal: -55), at: now)
        let comparison = MonitorComparison(samples: [sample], window: 3_600, now: now)

        XCTAssertNil(comparison.previousAverage)
        XCTAssertNil(comparison.delta)
    }

    func testLegacySnapshotWithoutPeersDecodes() throws {
        let data = Data(#"{"samples":[],"events":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(MonitorSnapshot.self, from: data)
        XCTAssertTrue(snapshot.peers.isEmpty)
        XCTAssertNil(snapshot.state)
    }

    func testDeauthBurstFromCaptureBecomesEvent() {
        var snapshot = MonitorSnapshot()
        let counter = ManagementCounters(
            bssid: "AA:BB:CC:DD:EE:01", deauth: 6, burst: true, lastSeen: start)
        let report = CaptureSecurityReport(management: [counter])

        XCTAssertTrue(snapshot.ingestCapture(report))
        XCTAssertEqual(snapshot.events.last?.kind, .deauthBurst)
        XCTAssertTrue(snapshot.events.last?.detail.contains("6") == true)
    }

    func testStoreRoundTripAndRetention() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-monitor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MonitorStore(directory: directory)
        var snapshot = MonitorSnapshot()
        let old = MonitorSample(
            network: makeNetwork(id: "old", signal: -60), at: start.addingTimeInterval(-7_200))
        let recent = MonitorSample(
            network: makeNetwork(id: "recent", signal: -50), at: start)
        snapshot.samples = [old, recent]
        snapshot.events = [
            MonitorEvent(at: old.at, kind: .connected, bssid: old.bssid, ssid: old.ssid, detail: "old"),
            MonitorEvent(at: recent.at, kind: .connected, bssid: recent.bssid, ssid: recent.ssid, detail: "new"),
        ]

        store.save(snapshot, retention: .hour, now: start)
        let loaded = store.load()

        XCTAssertEqual(loaded.samples.map(\.id), [recent.id])
        XCTAssertEqual(loaded.events.map(\.id), [snapshot.events[1].id])
    }

    func testCSVIncludesHeaderAndEscapesFields() {
        let sample = MonitorSample(
            network: makeNetwork(id: "a", ssid: "Cafe \"Guest\"", signal: -55), at: start)
        let csv = MonitorCSV.make(samples: [sample])

        XCTAssertTrue(csv.hasPrefix("timestamp,bssid,ssid,rssi,snr,channel,band,utilization,security\n"))
        XCTAssertTrue(csv.contains("\"Cafe \"\"Guest\"\"\""))
    }

    func testStatisticsUseSamples() {
        var snapshot = MonitorSnapshot()
        snapshot.ingest(connected: makeNetwork(id: "a", signal: -50), now: start, sampleInterval: 0)
        snapshot.ingest(
            connected: makeNetwork(id: "a", signal: -70), now: start.addingTimeInterval(5), sampleInterval: 0)

        let statistics = snapshot.statistics
        XCTAssertEqual(statistics?.minimum, -70)
        XCTAssertEqual(statistics?.maximum, -50)
        XCTAssertEqual(statistics?.count, 2)
    }
}
