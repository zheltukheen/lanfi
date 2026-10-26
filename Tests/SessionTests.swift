import XCTest

final class SessionTests: XCTestCase {
    func testSessionRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SessionStore(directory: directory)
        let network = makeNetwork(id: "session-network", ssid: "Session Wi-Fi", band: .band5, channel: 36)
        var annotation = NetworkAnnotation()
        annotation.alias = "Saved AP"

        let saved = try store.save(name: "Office", networks: [network], annotations: [network.id: annotation])
        XCTAssertEqual(saved.name, "Office")
        XCTAssertEqual(saved.networkCount, 1)

        let sessions = store.sessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.networks.first?.ssid, "Session Wi-Fi")
        XCTAssertEqual(sessions.first?.annotations[network.id]?.alias, "Saved AP")

        XCTAssertTrue(store.delete(saved))
        XCTAssertTrue(store.sessions().isEmpty)
    }

    func testSessionsAreSortedNewestFirst() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-session-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SessionStore(directory: directory)
        _ = try store.save(name: "First", networks: [], annotations: [:])
        Thread.sleep(forTimeInterval: 0.01)
        _ = try store.save(name: "Second", networks: [], annotations: [:])
        XCTAssertEqual(store.sessions().first?.name, "Second")
    }
}
