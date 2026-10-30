import XCTest

final class RFExplorerProtocolTests: XCTestCase {

    // A realistic `#C2-F:` line: 2400 MHz start, 50 kHz step, 112 points.
    private let configLine = "#C2-F:2400000,0050000,-020,-110,0112,0,000,0430000,6200000,1000000,00500,0000,000"

    func testParseConfigLine() {
        guard let config = RFExplorerProtocol.parseConfigLine(configLine) else {
            return XCTFail("config not parsed")
        }
        XCTAssertEqual(config.startMHz, 2400.0, accuracy: 0.0001)
        XCTAssertEqual(config.stepMHz, 0.05, accuracy: 0.000001)
        XCTAssertEqual(config.dataPoints, 112)
        XCTAssertEqual(config.amplitudeTopDBm, -20)
        XCTAssertEqual(config.amplitudeBottomDBm, -110)
        XCTAssertEqual(config.offsetDB, 0)
    }

    func testParseConfigLineRejectsOthers() {
        XCTAssertNil(RFExplorerProtocol.parseConfigLine("#C3-F:0221000,0020,0000100,0,0,1,00150"))
        XCTAssertNil(RFExplorerProtocol.parseConfigLine("#C2-F:240000,0050000,-020,-110,0112"))
        XCTAssertNil(RFExplorerProtocol.parseConfigLine("garbage"))
    }

    func testParseHighResConfigLine() {
        // `#C2-f:` uses 5 digits for the point count.
        let line = "#C2-f:2400000,0050000,-020,-110,00112,0,000,0430000,6200000,1000000,00500,0000,000"
        guard let config = RFExplorerProtocol.parseConfigLine(line) else {
            return XCTFail("config not parsed")
        }
        XCTAssertEqual(config.dataPoints, 112)
        XCTAssertEqual(config.startMHz, 2400.0, accuracy: 0.0001)
    }

    func testDecodeSweepPayload() {
        let config = RFExplorerProtocol.Config(
            startMHz: 2400, stepMHz: 0.05, dataPoints: 4,
            amplitudeTopDBm: -20, amplitudeBottomDBm: -110, offsetDB: 0
        )
        let values = RFExplorerProtocol.decodeSweepPayload([200, 100, 50, 255], config: config)
        XCTAssertEqual(values[0], -100.0, accuracy: 0.001)
        XCTAssertEqual(values[1], -50.0, accuracy: 0.001)
        XCTAssertEqual(values[2], -25.0, accuracy: 0.001)
        XCTAssertEqual(values[3], -127.5, accuracy: 0.001)
    }

    func testDecodeSweepPayloadPadsShortPayload() {
        let config = RFExplorerProtocol.Config(
            startMHz: 2400, stepMHz: 0.05, dataPoints: 3,
            amplitudeTopDBm: -20, amplitudeBottomDBm: -110, offsetDB: 0
        )
        let values = RFExplorerProtocol.decodeSweepPayload([200], config: config)
        XCTAssertEqual(values, [-100.0, -110.0, -110.0])
    }

    func testSweepPayloadLength() throws {
        XCTAssertEqual(RFExplorerProtocol.sweepPayloadLength(header: [0x24, 0x53, 5]), 5)  // $S
        XCTAssertEqual(RFExplorerProtocol.sweepPayloadLength(header: [0x24, 0x73, 3]), 48)  // $s ×16
        XCTAssertEqual(RFExplorerProtocol.sweepPayloadLength(header: [0x24, 0x73, 0]), 4096)  // $s zero → 256×16
        XCTAssertEqual(RFExplorerProtocol.sweepPayloadLength(header: [0x24, 0x7A, 1, 0]), 256)  // $z
        XCTAssertNil(RFExplorerProtocol.sweepPayloadLength(header: [0x24, 0x43, 1]))
        XCTAssertNil(RFExplorerProtocol.sweepPayloadLength(header: [0x23, 0x53, 1]))
    }

    func testFrameCommand() {
        let framed = RFExplorerProtocol.frameCommand("C0")
        XCTAssertEqual(Array(framed), [0x23, 0x04, 0x43, 0x30])  // "#\x04C0"
    }

    func testStreamParserConfigThenSweep() {
        var bytes = Array(configLine.utf8)
        bytes.append(contentsOf: [13, 10])
        // $S with 3 samples (112-point config pads the rest).
        bytes.append(contentsOf: [0x24, 0x53, 3, 200, 100, 50, 13, 10])
        let parser = RFExplorerProtocol.StreamParser()
        let events = parser.append(bytes)
        XCTAssertEqual(events.count, 2)
        guard case .config(let config) = events[0] else { return XCTFail("expected config") }
        XCTAssertEqual(config.dataPoints, 112)
        guard case .sweep(let sweep, _) = events[1] else { return XCTFail("expected sweep") }
        XCTAssertEqual(sweep.count, 112)
        XCTAssertEqual(sweep[0], -100.0, accuracy: 0.001)
        XCTAssertEqual(sweep[1], -50.0, accuracy: 0.001)
        XCTAssertEqual(sweep[2], -25.0, accuracy: 0.001)
        XCTAssertEqual(sweep[3], -110.0, accuracy: 0.001)  // padded to bottom of scale
    }

    func testStreamParserHandlesChunkedInput() {
        let parser = RFExplorerProtocol.StreamParser()
        var full = Array(configLine.utf8)
        full.append(contentsOf: [13, 10, 0x24, 0x53, 2, 200, 100, 13, 10])
        var events: [RFExplorerProtocol.StreamEvent] = []
        for byte in full {
            events.append(contentsOf: parser.append([byte]))
        }
        XCTAssertEqual(events.count, 2)
    }

    func testStreamParserResynchronisesAfterGarbage() {
        let parser = RFExplorerProtocol.StreamParser()
        var bytes: [UInt8] = [0x00, 0xFF, 0x24, 0x58, 0x11]  // garbage + unknown $X packet
        bytes.append(contentsOf: Array(configLine.utf8))
        bytes.append(contentsOf: [13, 10])
        let events = parser.append(bytes)
        XCTAssertEqual(events.count, 1)
        guard case .config = events[0] else { return XCTFail("expected config after resync") }
    }

    func testStreamParserDropsSweepBeforeConfig() {
        let parser = RFExplorerProtocol.StreamParser()
        let bytes: [UInt8] = [0x24, 0x53, 2, 200, 100, 13, 10]
        let events = parser.append(bytes)
        XCTAssertTrue(events.isEmpty)
        // Config afterwards is still parsed cleanly.
        var next = Array(configLine.utf8)
        next.append(contentsOf: [13, 10])
        XCTAssertEqual(parser.append(next).count, 1)
    }

    func testStreamParserSkipsCorruptedSweepTrailer() {
        let parser = RFExplorerProtocol.StreamParser()
        var bytes = Array(configLine.utf8)
        bytes.append(contentsOf: [13, 10])
        // Sweep announcing 2 bytes but with a wrong trailer.
        bytes.append(contentsOf: [0x24, 0x53, 2, 200, 100, 0x00, 0x00])
        // A good line afterwards must survive.
        bytes.append(contentsOf: Array("#Ok".utf8))
        bytes.append(contentsOf: [13, 10])
        let events = parser.append(bytes)
        XCTAssertEqual(events.count, 2)
        guard case .config = events[0] else { return XCTFail("expected config") }
        guard case .message(let text) = events[1] else { return XCTFail("expected message") }
        XCTAssertEqual(text, "#Ok")
    }
}
