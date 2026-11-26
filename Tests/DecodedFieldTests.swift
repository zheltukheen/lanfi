import XCTest

final class DecodedFieldTests: XCTestCase {
    private func element(
        _ id: String, elementId: Int = 255, name: String, summary: String,
        detail: [String] = []
    ) -> InformationElement {
        InformationElement(
            id: id, elementId: elementId, length: 8, name: name, summary: summary,
            detailLines: detail, rawHex: "")
    }

    private func fullNetwork() -> NetworkModel {
        makeNetwork(
            bssid: "AA:BB:CC:DD:EE:01", ssid: "Lab", band: .band6, channel: 37, width: 160,
            signal: -55, wpsEnabled: true, pmfRequired: true,
            informationElements: [
                element(
                    "mlo", name: "Extension: Multi-Link", summary: "Multi-Link",
                    detail: [
                        "AP MLD address: AA:BB:CC:DD:EE:99",
                        "Per-STA profile link IDs: 1, 2",
                        "Link 1 BSSID: 11:22:33:44:55:66",
                    ]),
                element(
                    "vendor", elementId: 221, name: "Vendor Specific",
                    summary: "Vendor: Cisco · Data: 00 01 02"),
            ])
    }

    func testCatalogueKeysAreUniqueAndClean() {
        let fields = DecodedFieldCatalog.fields(for: fullNetwork())
        XCTAssertFalse(fields.isEmpty)
        XCTAssertEqual(Set(fields.map(\.key)).count, fields.count)
        for field in fields {
            XCTAssertFalse(field.value.isEmpty, "Empty value for \(field.key)")
            XCTAssertFalse(field.value.contains("Optional("), "Optional leaked in \(field.key)")
            XCTAssertFalse(field.value.contains("\n"), "Newline in \(field.key)")
        }
    }

    func testValueLookupMatchesTheCatalogue() {
        let network = fullNetwork()
        let fields = DecodedFieldCatalog.fields(for: network)
        for field in fields {
            XCTAssertEqual(DecodedFieldCatalog.value(for: field.key, network: network), field.value)
        }
        XCTAssertNil(DecodedFieldCatalog.value(for: "sixghz.powermode", network: network))
    }

    func testVendorAndMLOElementsBecomeAddressableFields() {
        let network = fullNetwork()
        let fields = DecodedFieldCatalog.fields(for: network)
        XCTAssertEqual(
            fields.first { $0.key == "mlo.apmld" }?.value, "AA:BB:CC:DD:EE:99")
        XCTAssertEqual(
            fields.first { $0.key == "mlo.links" }?.value,
            "1: 11:22:33:44:55:66, 2")
        XCTAssertEqual(fields.first { $0.key == "mlo.320mhz" }?.value, "No")
        XCTAssertEqual(
            fields.first { $0.key == "ie.element.221.0" }?.value,
            "Vendor: Cisco · Data: 00 01 02")
        XCTAssertEqual(
            fields.first { $0.key == "security.pmf" }?.value, "Yes")
    }

    func testRepeatedElementIdsGetDistinctKeys() {
        let network = makeNetwork(informationElements: [
            element("a", elementId: 221, name: "Vendor Specific", summary: "First"),
            element("b", elementId: 221, name: "Vendor Specific", summary: "Second"),
        ])
        let fields = DecodedFieldCatalog.fields(for: network)
        XCTAssertEqual(fields.first { $0.key == "ie.element.221.0" }?.value, "First")
        XCTAssertEqual(fields.first { $0.key == "ie.element.221.1" }?.value, "Second")
    }

    func testBareNetworkProducesNoMloOrSixGHzFields() {
        let fields = DecodedFieldCatalog.fields(for: makeNetwork())
        XCTAssertTrue(fields.allSatisfy { !$0.key.hasPrefix("mlo.") })
        XCTAssertTrue(fields.allSatisfy { !$0.key.hasPrefix("sixghz.") })
    }

    func testAllFieldsCSVHasAUnionHeaderAndAlignedRows() {
        let withVendor = makeNetwork(
            bssid: "AA:00:00:00:00:01",
            informationElements: [
                element("v", elementId: 221, name: "Vendor Specific", summary: "Cisco · 1, 2")
            ])
        let withMLO = makeNetwork(
            bssid: "AA:00:00:00:00:02",
            informationElements: [
                element(
                    "m", name: "Extension: Multi-Link", summary: "Multi-Link",
                    detail: ["AP MLD address: AA:BB:CC:DD:EE:99"])
            ])
        let csv = DecodedFieldCSVExporter().make(networks: [withVendor, withMLO])
        let lines = csv.split(separator: "\r\n")
        XCTAssertEqual(lines.count, 3)

        let header = csvRow(lines[0])
        let vendorColumn = header.firstIndex(of: "ie.element.221.0")
        let mloColumn = header.firstIndex(of: "mlo.apmld")
        XCTAssertNotNil(vendorColumn)
        XCTAssertNotNil(mloColumn)

        let vendorRow = csvRow(lines[1])
        let mloRow = csvRow(lines[2])
        XCTAssertEqual(vendorRow.count, header.count)
        XCTAssertEqual(mloRow.count, header.count)
        XCTAssertEqual(vendorRow[vendorColumn!], "Cisco · 1, 2")
        XCTAssertEqual(mloRow[vendorColumn!], "")
        XCTAssertEqual(mloRow[mloColumn!], "AA:BB:CC:DD:EE:99")
    }

    /// Quote-aware split: a vendor summary can contain a comma.
    private func csvRow(_ line: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == "," && !quoted {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        result.append(current)
        return result
    }
}
