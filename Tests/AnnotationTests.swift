import XCTest

final class AnnotationTests: XCTestCase {
    func testAnnotationStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-annotation-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AnnotationStore(directory: directory)
        var annotation = NetworkAnnotation()
        annotation.alias = "Lobby AP"
        annotation.notes = "Near the reception desk"
        annotation.tags = ["guest", "priority"]
        store.update(annotation, for: "00:1A:2B:11:22:33")
        store.flush()

        let reloaded = AnnotationStore(directory: directory)
        let loaded = reloaded.annotation(for: "00:1A:2B:11:22:33")
        XCTAssertEqual(loaded.alias, "Lobby AP")
        XCTAssertEqual(loaded.notes, "Near the reception desk")
        XCTAssertEqual(loaded.tags, ["guest", "priority"])
        XCTAssertNotEqual(loaded.updatedAt, .distantPast)
    }

    func testEmptyAnnotationRemovesRecord() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-annotation-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AnnotationStore(directory: directory)
        var annotation = NetworkAnnotation()
        annotation.alias = "Temporary"
        store.update(annotation, for: "id")
        store.update(NetworkAnnotation(), for: "id")
        XCTAssertTrue(store.annotation(for: "id").isEmpty)
    }

    func testFormatterUsesAliasAndTags() {
        let network = makeNetwork(id: "annotated", ssid: "Raw SSID")
        var annotation = NetworkAnnotation()
        annotation.alias = "My Router"
        annotation.tags = ["home"]
        annotation.notes = "Living room"

        let formatter = NetworkColumnFormatter(
            signalDisplayMode: .dbm,
            connectedBSSID: nil,
            metricsByNetworkId: [:],
            annotationsByNetworkId: [network.id: annotation]
        )
        XCTAssertEqual(formatter.text(for: .networkName, network: network), "My Router")
        XCTAssertEqual(formatter.text(for: .apName, network: network), "My Router")
        XCTAssertTrue(formatter.text(for: .annotations, network: network).contains("home"))
        XCTAssertTrue(formatter.text(for: .annotations, network: network).contains("Note"))
    }
}
