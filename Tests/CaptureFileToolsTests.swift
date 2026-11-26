import XCTest

final class CaptureFileToolsTests: XCTestCase {
    // MARK: - Rotated parts

    func testRotatedPartsAreMergedInOrderAndRemoved() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let base = folder.appendingPathComponent("capture.pcap")
        let beaconA = Self.beacon(ssid: "First")
        let beaconB = Self.beacon(ssid: "Second")
        try Self.pcap(frames: [beaconA]).write(to: base)
        try Self.pcap(frames: [beaconB]).write(to: URL(fileURLWithPath: base.path + "1"))

        XCTAssertEqual(CaptureFiles.partURLs(base: base).count, 2)
        try CaptureFiles.mergeParts(base: base)

        XCTAssertEqual(CaptureFiles.partURLs(base: base).count, 1)
        let merged = try Data(contentsOf: base)
        let beacons = try PcapAnalyzer.parse(data: merged)
        XCTAssertEqual(beacons.count, 2)
        XCTAssertEqual(beacons.map(\.ssid), ["First", "Second"])
    }

    func testPartsWithDifferentLinkTypesAreRefused() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let base = folder.appendingPathComponent("capture.pcap")
        try Self.pcap(frames: [Self.beacon(ssid: "A")]).write(to: base)
        var ethernet = Self.pcap(frames: [Data(repeating: 0, count: 60)])
        ethernet.replaceSubrange(20..<24, with: [1, 0, 0, 0])
        try ethernet.write(to: URL(fileURLWithPath: base.path + "1"))

        XCTAssertThrowsError(try CaptureFiles.mergeParts(base: base)) { error in
            guard case CaptureFileError.linkTypeMismatch = error else {
                return XCTFail("expected a link-type mismatch, got \(error)")
            }
        }
    }

    // MARK: - Slicing

    func testDataFramesAreTruncatedAndManagementFramesKeptWhole() throws {
        let dataFrame = Self.dataFrame(payload: 40)
        let beacon = Self.beacon(ssid: "Whole")
        let original = Self.pcap(frames: [dataFrame, beacon])

        let sliced = try XCTUnwrap(PcapDataFrameSlicer.slice(original, maxDataFrameBytes: 32))
        let records = Self.records(in: sliced)
        XCTAssertEqual(records.count, 2)
        // Radiotap (8) + 802.11 header (24) already exceeds the limit, so the
        // whole frame is capped at 32 rather than keeping a partial header.
        XCTAssertEqual(records[0].included, 32)
        XCTAssertEqual(records[0].original, UInt32(dataFrame.count))
        XCTAssertEqual(records[1].included, UInt32(beacon.count))
        XCTAssertEqual(records[1].original, UInt32(beacon.count))
    }

    func testSlicingLeavesPcapngAlone() throws {
        var pcapng = Data([0x0A, 0x0D, 0x0D, 0x0A])
        pcapng.append(Data(repeating: 0, count: 28))
        XCTAssertNil(PcapDataFrameSlicer.slice(pcapng, maxDataFrameBytes: 32))
    }

    func testSliceInPlaceRewritesTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-slice-\(UUID().uuidString).pcap")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Self.pcap(frames: [Self.dataFrame(payload: 200), Self.beacon(ssid: "B")])
        try original.write(to: url)

        XCTAssertTrue(
            try PcapDataFrameSlicer.sliceInPlace(url: url, maxDataFrameBytes: 64))
        let rewritten = try Data(contentsOf: url)
        XCTAssertLessThan(rewritten.count, original.count)
        XCTAssertEqual(Self.records(in: rewritten).first?.included, 64)
    }

    // MARK: - Fixtures

    /// A radiotap-wrapped beacon with one SSID element — enough for the
    /// analyzer to name it and for the slicer to see a management frame.
    private static func beacon(ssid: String) -> Data {
        var frame = Data()
        frame.append(contentsOf: [0x80, 0x00])  // beacon
        frame.append(contentsOf: [0, 0])  // duration
        frame.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))  // broadcast
        frame.append(contentsOf: [0x02, 0, 0, 0, 0, 0x01])  // bssid
        frame.append(contentsOf: [0x02, 0, 0, 0, 0, 0x01])
        frame.append(contentsOf: [0, 0])  // sequence
        frame.append(contentsOf: [UInt8](repeating: 0, count: 8))  // timestamp
        frame.append(contentsOf: [0x64, 0x00])  // beacon interval
        frame.append(contentsOf: [0x01, 0x00])  // capability
        frame.append(contentsOf: [0, UInt8(ssid.utf8.count)] + Array(ssid.utf8))
        frame.append(contentsOf: [1, 1, 0x82])  // supported rates
        return radiotap() + frame
    }

    /// A radiotap-wrapped data frame with `payload` bytes after its header.
    private static func dataFrame(payload: Int) -> Data {
        var frame = Data([0x08, 0x02])  // data, to DS
        frame.append(contentsOf: [UInt8](repeating: 0x11, count: 22))
        frame.append(Data(repeating: 0xAB, count: payload))
        return radiotap() + frame
    }

    private static func radiotap() -> Data {
        Data([0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    private static func pcap(frames: [Data]) -> Data {
        var data = Data()
        data.append(contentsOf: littleEndian(UInt32(0xA1B2_C3D4)))
        data.append(contentsOf: littleEndian(UInt16(2)))
        data.append(contentsOf: littleEndian(UInt16(4)))
        data.append(contentsOf: littleEndian(UInt32(0)))
        data.append(contentsOf: littleEndian(UInt32(0)))
        data.append(contentsOf: littleEndian(UInt32(65_535)))
        data.append(contentsOf: littleEndian(UInt32(127)))
        for (index, frame) in frames.enumerated() {
            data.append(contentsOf: littleEndian(UInt32(1_700_000_000 + index)))
            data.append(contentsOf: littleEndian(UInt32(0)))
            data.append(contentsOf: littleEndian(UInt32(frame.count)))
            data.append(contentsOf: littleEndian(UInt32(frame.count)))
            data.append(frame)
        }
        return data
    }

    private static func records(in data: Data) -> [(included: UInt32, original: UInt32)] {
        var result: [(UInt32, UInt32)] = []
        var offset = 24
        while offset + 16 <= data.count {
            let included = readUInt32(data, at: offset + 8)
            let original = readUInt32(data, at: offset + 12)
            result.append((included, original))
            offset += 16 + Int(included)
        }
        return result
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }
}
