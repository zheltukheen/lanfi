import Foundation
import XCTest

final class MCPLiveActionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRequestRoundTripsThroughTheInbox() throws {
        let request = MCPLiveActionRequest(
            action: .scanNow, arguments: ["reason": "test"])
        try MCPLiveActionStore.submit(request, directory: directory)

        let pending = MCPLiveActionStore.pending(directory: directory)
        XCTAssertEqual(pending.map(\.id), [request.id])
        XCTAssertEqual(pending.first?.action, .scanNow)
        XCTAssertEqual(pending.first?.arguments["reason"], "test")

        MCPLiveActionStore.take(request, directory: directory)
        XCTAssertTrue(MCPLiveActionStore.pending(directory: directory).isEmpty)
    }

    func testResponseIsReadByID() throws {
        let request = MCPLiveActionRequest(action: .surveySample)
        let response = MCPLiveActionResponse(
            id: request.id, action: .surveySample, ok: true, message: "done",
            payload: ["latitude": "51.5"])
        try MCPLiveActionStore.respond(response, directory: directory)

        XCTAssertEqual(
            MCPLiveActionStore.response(id: request.id, directory: directory), response)
        XCTAssertNil(
            MCPLiveActionStore.response(id: UUID(), directory: directory))
    }

    func testWaitTimesOutWithoutAnAnswer() {
        let started = Date()
        let response = MCPLiveActionStore.waitForResponse(
            id: UUID(), directory: directory, timeout: 0.2)
        XCTAssertNil(response)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testPendingIgnoresUndecodableFiles() throws {
        let request = MCPLiveActionRequest(action: .startCapture)
        try MCPLiveActionStore.submit(request, directory: directory)
        let folder = directory.appendingPathComponent("inbox", isDirectory: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.json"))

        XCTAssertEqual(
            MCPLiveActionStore.pending(directory: directory).map(\.id), [request.id])
    }

    func testPruneRemovesOldFiles() throws {
        let request = MCPLiveActionRequest(action: .scanNow)
        try MCPLiveActionStore.submit(request, directory: directory)
        let file =
            directory
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("\(request.id.uuidString).json")
        let old = Date().addingTimeInterval(-3600)
        try FileManager.default.setAttributes(
            [.modificationDate: old], ofItemAtPath: file.path)

        MCPLiveActionStore.prune(directory: directory, olderThan: 600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRegistryAdvertisesTheLiveTools() {
        let names = Set(MCPToolRegistry.names)
        XCTAssertTrue(names.contains("lanfi_scan_now"))
        XCTAssertTrue(names.contains("lanfi_start_capture"))
        XCTAssertTrue(names.contains("lanfi_survey_sample"))
        XCTAssertTrue(names.contains("lanfi_scan_summary"), "read-only tools stay")
    }
}
