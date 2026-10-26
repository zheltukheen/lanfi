import XCTest

final class DiagnosticsBundleTests: XCTestCase {
    func testBundleContainsReportsAndReadme() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-bundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = DiagnosticsReport(
            id: "one", startedAt: Date(), finishedAt: Date(), snapshot: .empty, checks: []
        )
        let zip = try DiagnosticsBundleExporter.makeBundle(
            report: report, history: [report], interfaces: .empty, directory: directory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        XCTAssertEqual(zip.pathExtension, "zip")

        let expanded = directory.appendingPathComponent("expanded", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, expanded.path]
        try process.run()
        process.waitUntilExit()
        let root = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: expanded, includingPropertiesForKeys: nil).first
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("README.txt").path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("diagnostics-report.json").path)
        )
    }
}
