import XCTest

final class SecurityParserTests: XCTestCase {
    func testWPA3TransitionAndPMF() throws {
        // RSN: version 1, group CCMP, 1 pairwise CCMP, AKMs PSK + SAE, MFPR.
        var bytes: [UInt8] = [1, 0]
        bytes += [0x00, 0x0F, 0xAC, 4]
        bytes += [1, 0, 0x00, 0x0F, 0xAC, 4]
        bytes += [2, 0, 0x00, 0x0F, 0xAC, 2, 0x00, 0x0F, 0xAC, 8]
        bytes += [0x40, 0x00]
        let ie: [UInt8] = [48, UInt8(bytes.count)] + bytes
        let info = try XCTUnwrap(SecurityParser.parse(Data(ie)))
        XCTAssertEqual(info.label, "WPA3 Transition")
        XCTAssertTrue(info.pmfRequired)
    }

    func testWPA2Personal() throws {
        var bytes: [UInt8] = [1, 0]
        bytes += [0x00, 0x0F, 0xAC, 4]
        bytes += [1, 0, 0x00, 0x0F, 0xAC, 4]
        bytes += [1, 0, 0x00, 0x0F, 0xAC, 2]
        bytes += [0x00, 0x00]
        let ie: [UInt8] = [48, UInt8(bytes.count)] + bytes
        let info = try XCTUnwrap(SecurityParser.parse(Data(ie)))
        XCTAssertEqual(info.label, "WPA2 Personal")
    }
}
