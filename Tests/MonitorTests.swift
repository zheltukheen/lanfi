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
