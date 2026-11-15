import XCTest

final class OUIParserTests: XCTestCase {
    func testBuiltInVendorLookup() {
        XCTAssertEqual(OUIParser.vendor(for: "00:1B:63:11:22:33"), "Apple, Inc.")
        XCTAssertEqual(OUIParser.vendor(for: "b8-27-eb-00-11-22"), "Raspberry Pi Foundation")
    }

    func testKnownOUIUsesOfficialName() {
        XCTAssertEqual(OUIParser.vendor(for: "00:1A:2B:11:22:33"), "Ayecom Technology Co., Ltd.")
    }

    func testLocallyAdministeredMACIsRandomised() {
        XCTAssertEqual(OUIParser.vendor(for: "02:00:00:00:00:01"), "Randomized MAC")
        XCTAssertEqual(OUIParser.vendor(for: "DA:AA:BB:CC:DD:EE"), "Randomized MAC")
    }

    func testInvalidOrEmptyBSSID() {
        XCTAssertEqual(OUIParser.vendor(for: ""), "-")
        XCTAssertEqual(OUIParser.vendor(for: "not-a-mac"), "-")
    }

    func testLongestPrefixWins() {
        let database = [
            "001A2B": "24-bit Vendor",
            "001A2B0": "28-bit Vendor",
            "001A2B0C1": "36-bit Vendor",
        ]
        XCTAssertEqual(OUIParser.lookup(mac: "00:1A:2B:0C:11:22", in: database), "36-bit Vendor")
        XCTAssertEqual(OUIParser.lookup(mac: "00:1A:2B:0D:11:22", in: database), "28-bit Vendor")
        XCTAssertEqual(OUIParser.lookup(mac: "00:1A:2B:FF:11:22", in: database), "24-bit Vendor")
        XCTAssertNil(OUIParser.lookup(mac: "00:00:00:00:00:00", in: database))
    }

    func testPackedIndexMatchesStringLookup() {
        let database = [
            "001A2B": "24-bit Vendor",
            "001A2B0": "28-bit Vendor",
            "001A2B0C1": "36-bit Vendor",
        ]
        let index = OUIParser.packedIndex(from: database)
        for mac in ["00:1A:2B:0C:11:22", "00:1A:2B:0D:11:22", "00:1A:2B:FF:11:22"] {
            XCTAssertEqual(
                OUIParser.lookupPacked(mac: mac, in: index),
                OUIParser.lookup(mac: mac, in: database))
        }
        XCTAssertNil(OUIParser.lookupPacked(mac: "00:00:00:00:00:00", in: index))
    }

    func testDatabaseParserIgnoresMalformedLines() {
        let text = """
            # comment
            001A2B\tApple
            001A2B0\tApple 28
            001A2B0C1\tApple 36
            broken line
            ZZ\tInvalid
            12345\tToo short
            """
        let database = OUIParser.parseDatabase(text)
        XCTAssertEqual(database["001A2B"], "Apple")
        XCTAssertEqual(database["001A2B0"], "Apple 28")
        XCTAssertEqual(database["001A2B0C1"], "Apple 36")
        XCTAssertEqual(database.count, 3)
    }

    func testCustomOverrideInvalidatesCachedLookup() {
        let prefix = "00:1A:2C"
        defer { OUIParser.removeOverride(prefix) }

        XCTAssertTrue(OUIParser.setOverride(prefix: prefix, vendor: "First Vendor"))
        XCTAssertEqual(OUIParser.vendor(for: "\(prefix):11:22:33"), "First Vendor")

        XCTAssertTrue(OUIParser.setOverride(prefix: prefix, vendor: "Second Vendor"))
        XCTAssertEqual(OUIParser.vendor(for: "\(prefix):11:22:33"), "Second Vendor")

        OUIParser.removeOverride(prefix)
        XCTAssertNotEqual(OUIParser.vendor(for: "\(prefix):11:22:33"), "Second Vendor")
    }

    func testCustomOverrideSupportsLongerPrefix() {
        let prefix = "00:1A:2C:0"
        defer { OUIParser.removeOverride(prefix) }

        XCTAssertTrue(OUIParser.setOverride(prefix: prefix, vendor: "Long Prefix"))
        XCTAssertEqual(OUIParser.vendor(for: "00:1A:2C:0A:11:22"), "Long Prefix")
        XCTAssertNotEqual(OUIParser.vendor(for: "00:1A:2C:1A:11:22"), "Long Prefix")
    }

    func testMacNormalizationAcceptsCommonFormats() {
        XCTAssertEqual(OUIParser.normalizedMAC("00:1a:2b:0c:11:22"), "001A2B0C1122")
        XCTAssertEqual(OUIParser.normalizedMAC("00-1A-2B-0C-11-22"), "001A2B0C1122")
        XCTAssertEqual(OUIParser.normalizedMAC("001A.2B0C.1122"), "001A2B0C1122")
        XCTAssertEqual(OUIParser.normalizedMAC("not-a-mac"), "")
    }
}
