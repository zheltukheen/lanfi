import XCTest

/// The live capture is the supervisor's first real consumer: readiness is the
/// pcap header tcpdump writes once BPF is open, which is what lets a stuck
/// prompt or a stuck tcpdump end in an error instead of a frozen window.
final class LiveCaptureWiringTests: XCTestCase {
    func testCaptureOnlyCountsAsStartedAfterThePcapHeader() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-capture-\(UUID().uuidString).pcap")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(LiveCaptureService.captureHasStarted(at: url), "no file yet")
        try Data(repeating: 0, count: 10).write(to: url)
        XCTAssertFalse(LiveCaptureService.captureHasStarted(at: url), "a partial file is not ready")
        try Data(repeating: 0, count: 24).write(to: url)
        XCTAssertTrue(LiveCaptureService.captureHasStarted(at: url), "the header means BPF is open")
    }

    func testCancelledPromptIsReportedAsCancellation() {
        guard
            case .authorizationCancelled = LiveCaptureService.captureError(
                from: "execution error: User canceled. (-128)")
        else {
            return XCTFail("a cancelled prompt must map to authorizationCancelled")
        }
    }

    func testEmptyErrorExplainsThatTheCaptureDidNotStart() {
        guard case .captureFailed(let message) = LiveCaptureService.captureError(from: "") else {
            return XCTFail("expected captureFailed")
        }
        XCTAssertTrue(message.contains("did not start"), message)
    }
}
