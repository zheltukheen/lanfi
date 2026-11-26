import XCTest

@MainActor
final class NetworkBaselineTests: XCTestCase {
    private func network(
        _ bssid: String, ssid: String = "Corp", channel: Int = 36, signal: Int = -60
    ) -> NetworkModel {
        makeNetwork(
            bssid: bssid, ssid: ssid, band: .band5, channel: channel, signal: signal)
    }

    private func store() -> (NetworkBaselineStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-baseline-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return (NetworkBaselineStore(url: url), url)
    }

    func testFirstScanSeedsSilently() {
        let (store, _) = store()
        let service = NetworkBaselineService(store: store, postsEvents: false)
        XCTAssertFalse(service.isSeeded)

        service.observe([
            network("AA:00:00:00:00:01"),
            network("AA:00:00:00:00:02", ssid: "Guest"),
        ])

        XCTAssertTrue(service.isSeeded)
        XCTAssertEqual(service.knownCount, 2)
        XCTAssertTrue(service.pending.isEmpty)
    }

    func testNewBSSIDAppearsOnceAndStaysPending() {
        let (store, _) = store()
        let service = NetworkBaselineService(store: store, postsEvents: false)
        service.observe([network("AA:00:00:00:00:01")])

        let newcomer = network("AA:00:00:00:00:09", ssid: "New", channel: 44, signal: -70)
        service.observe([network("AA:00:00:00:00:01"), newcomer])
        XCTAssertEqual(service.pending.map(\.bssid), ["AA:00:00:00:00:09"])
        XCTAssertEqual(service.pending.first?.channel, 44)
        XCTAssertEqual(service.pending.first?.signal, -70)
        XCTAssertEqual(service.knownCount, 1)

        // Watching the same newcomer on later scans does not duplicate it.
        service.observe([newcomer])
        XCTAssertEqual(service.pending.count, 1)
    }

    func testAcceptingPendingMovesItIntoTheBaseline() {
        let (store, _) = store()
        let service = NetworkBaselineService(store: store, postsEvents: false)
        service.observe([network("AA:00:00:00:00:01")])
        service.observe([network("AA:00:00:00:00:02")])
        XCTAssertEqual(service.pending.count, 1)

        service.acceptPending()
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertEqual(service.knownCount, 2)

        service.observe([network("AA:00:00:00:00:02")])
        XCTAssertTrue(service.pending.isEmpty)
    }

    func testResetSeedsTheNextScanWithoutAlerts() {
        let (store, _) = store()
        let service = NetworkBaselineService(store: store, postsEvents: false)
        service.observe([network("AA:00:00:00:00:01")])
        service.observe([network("AA:00:00:00:00:02")])
        XCTAssertEqual(service.pending.count, 1)

        service.reset()
        XCTAssertFalse(service.isSeeded)
        XCTAssertEqual(service.knownCount, 0)
        XCTAssertTrue(service.pending.isEmpty)

        service.observe([network("AA:00:00:00:00:03"), network("AA:00:00:00:00:04")])
        XCTAssertTrue(service.isSeeded)
        XCTAssertEqual(service.knownCount, 2)
        XCTAssertTrue(service.pending.isEmpty)
    }

    func testPendingSurvivesARelaunch() {
        let (store, _) = store()
        let first = NetworkBaselineService(store: store, postsEvents: false)
        first.observe([network("AA:00:00:00:00:01")])
        first.observe([network("AA:00:00:00:00:02", ssid: "New")])

        let second = NetworkBaselineService(store: store, postsEvents: false)
        XCTAssertEqual(second.pending.map(\.bssid), ["AA:00:00:00:00:02"])
        XCTAssertTrue(second.isSeeded)
    }

    func testEvaluatorSkipsEmptyAndDuplicateBSSIDs() {
        let state = NetworkBaselineState(seededAt: Date())
        let unseen = NetworkBaselineEvaluator.unseen(
            networks: [
                network("AA:00:00:00:00:01"),
                network("aa:00:00:00:00:01"),
                network(""),
            ],
            state: state)
        XCTAssertEqual(unseen.map(\.bssid), ["AA:00:00:00:00:01"])
    }

    func testHiddenSSIDGetsAReadableLabel() {
        let state = NetworkBaselineState(seededAt: Date())
        let unseen = NetworkBaselineEvaluator.unseen(
            networks: [network("AA:00:00:00:00:07", ssid: "")], state: state)
        XCTAssertEqual(unseen.first?.ssid, "Hidden network")
    }
}
