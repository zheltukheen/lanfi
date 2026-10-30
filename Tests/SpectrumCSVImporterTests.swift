import XCTest

final class SpectrumCSVImporterTests: XCTestCase {
    func testParsesGenericTwoColumnCSV() {
        let csv = "2400.000,-90.5\n2400.050,-70.0\n2400.100,-50.0\n"
        let sweep = SpectrumCSVImporter.parse(csv)
        XCTAssertNotNil(sweep)
        XCTAssertEqual(sweep?.startMHz ?? -1, 2400.0, accuracy: 0.001)
        XCTAssertEqual(sweep?.stepMHz ?? -1, 0.05, accuracy: 0.0001)
        XCTAssertEqual(sweep?.amplitudes, [-90.5, -70.0, -50.0])
        XCTAssertEqual(sweep?.pointCount, 3)
    }

    func testParsesChanalyzerStyleExportWithHeader() {
        let csv = """
            Frequency (MHz),Amplitude (dBm)
            2412.000,-80.0
            2412.044,-79.5
            2412.088,-79.0
            """
        let sweep = SpectrumCSVImporter.parse(csv, source: "Chanalyzer.csv")
        XCTAssertEqual(sweep?.source, "Chanalyzer.csv")
        XCTAssertEqual(sweep?.pointCount, 3)
        XCTAssertEqual(sweep?.startMHz ?? -1, 2412.0, accuracy: 0.001)
    }

    func testAcceptsSemicolonAndTabSeparators() {
        XCTAssertNotNil(SpectrumCSVImporter.parse("2400.0;-90.0\n2400.1;-80.0"))
        XCTAssertNotNil(SpectrumCSVImporter.parse("2400\t-90\n2401\t-80"))
    }

    func testRejectsGarbageAndSinglePoint() {
        XCTAssertNil(SpectrumCSVImporter.parse("not,a,spectrum\n1,2"))
        XCTAssertNil(SpectrumCSVImporter.parse("2400.0,-90.0\n"))
        XCTAssertNil(SpectrumCSVImporter.parse(""))
    }

    func testExporterRoundTripsThroughImporter() {
        let original = SpectrumSweep(
            source: "roundtrip", capturedAt: Date(timeIntervalSince1970: 0),
            startMHz: 5180, stepMHz: 0.1, amplitudes: [-95.5, -60.25, -40.0]
        )
        let text = SpectrumCSVExporter.csv(original)
        guard let parsed = SpectrumCSVImporter.parse(text) else { return XCTFail("re-import failed") }
        XCTAssertEqual(parsed.startMHz, original.startMHz, accuracy: 0.001)
        XCTAssertEqual(parsed.pointCount, original.pointCount)
        XCTAssertEqual(parsed.amplitudes[0], original.amplitudes[0], accuracy: 0.05)
        XCTAssertEqual(parsed.amplitudes[1], original.amplitudes[1], accuracy: 0.05)
        XCTAssertEqual(parsed.amplitudes[2], original.amplitudes[2], accuracy: 0.05)
    }
}
