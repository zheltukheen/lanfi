import XCTest

final class ProtocolAnalyzerTests: XCTestCase {

    func testProfileContainsAllProtocolBlocks() {
        let network = makeNetwork(
            id: "proto",
            ssid: "Corp Wi-Fi",
            band: .band6,
            channel: 37,
            width: 160,
            generation: .mode11be,
            security: "WPA3 Enterprise",
            signal: -52,
            noise: -96,
            snr: 44,
            utilization: 12,
            centerFrequency: 6135,
            clients: 12,
            stations: 14,
            wpsEnabled: false,
            pmfRequired: true
        )
        let metrics = NetworkAnalyzer.metricsFor(network, among: [network])
        let profile = ProtocolAnalyzer.profile(for: network, metrics: metrics)

        XCTAssertEqual(profile.blocks.count, 6)
        XCTAssertEqual(Set(profile.blocks.map(\.id)).count, 6)
        XCTAssertEqual(profile.formatLine, "6GHz · 11be · 160 MHz · WPA3 Enterprise")
        XCTAssertEqual(profile.band, .band6)
        XCTAssertTrue(profile.blocks.allSatisfy { !$0.facts.isEmpty })
        XCTAssertTrue(profile.blocks.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })

        let security = profile.blocks.first { $0.id == "security" }
        XCTAssertEqual(security?.facts.first?.value, "WPA3 Enterprise")
        XCTAssertEqual(security?.status, .good)

        let radio = profile.blocks.first { $0.id == "radio" }
        XCTAssertEqual(radio?.facts.first?.value, "11be")
        XCTAssertTrue(radio?.facts.contains { $0.id == "band" && $0.value == "6GHz" } == true)
    }

    func testOpenAndWEPNetworksAreCritical() {
        for security in ["Open", "WEP"] {
            let network = makeNetwork(security: security)
            let profile = ProtocolAnalyzer.profile(for: network, metrics: nil)
            let block = profile.blocks.first { $0.id == "security" }
            XCTAssertEqual(block?.status, .critical, "\(security) should be critical")
            XCTAssertTrue(profile.warnings.contains { $0.contains("Security") })
        }
    }

    func testWPSAndLegacyWPAWarn() {
        let network = makeNetwork(security: "WPA Personal", wpsEnabled: true)
        let profile = ProtocolAnalyzer.profile(for: network, metrics: nil)
        XCTAssertEqual(profile.blocks.first { $0.id == "security" }?.status, .warning)
        XCTAssertTrue(profile.warnings.contains { $0.contains("WPS") || $0.contains("WPA") })
    }

    func testHiddenAndUnknownNetworksStayReadable() {
        let network = makeNetwork(
            id: "hidden",
            bssid: "",
            ssid: "",
            band: .unknown,
            channel: 0,
            width: 0,
            generation: .unknown,
            security: "Unknown",
            signal: -100,
            noise: nil,
            snr: nil,
            utilization: nil,
            centerFrequency: nil,
            clients: nil,
            stations: nil
        )
        let profile = ProtocolAnalyzer.profile(for: network, metrics: nil)

        XCTAssertEqual(profile.title, "<Hidden>")
        XCTAssertEqual(profile.subtitle, "No BSSID")
        XCTAssertTrue(profile.blocks.allSatisfy { !$0.facts.isEmpty })
        let format = profile.blocks.first { $0.id == "format" }
        XCTAssertTrue(format?.facts.contains { $0.label == "SSID visibility" && $0.value == "Hidden" } == true)
        XCTAssertFalse(profile.formatLine.contains("Optional"))
    }

    func testInformationElementsDriveMobilityDetection() {
        let rm = InformationElement(
            id: "70-1", elementId: 70, length: 5, name: "RM Enabled Capabilities",
            summary: "Link Measurement, Neighbor Report", detailLines: [], rawHex: "00"
        )
        let extended = InformationElement(
            id: "127-1", elementId: 127, length: 8, name: "Extended Capabilities",
            summary: "BSS Transition, TWT Responder", detailLines: [], rawHex: "00"
        )
        let network = makeNetwork(security: "WPA2 Enterprise", informationElements: [rm, extended])
        let profile = ProtocolAnalyzer.profile(for: network, metrics: nil)
        let mobility = profile.blocks.first { $0.id == "mobility" }

        XCTAssertTrue(mobility?.facts.contains { $0.id == "rm" && $0.value == "Supported" } == true)
        XCTAssertTrue(mobility?.facts.contains { $0.id == "bss" && $0.value == "Supported" } == true)
        XCTAssertTrue(mobility?.facts.contains { $0.id == "twt" } == true)
        XCTAssertEqual(mobility?.status, .good)
    }

    func testCoverageCountsBandsAndSecurity() {
        let networks = [
            makeNetwork(id: "a", band: .band24, generation: .mode11ax, security: "WPA2 Personal"),
            makeNetwork(id: "b", band: .band5, generation: .mode11ac, security: "WPA3 Personal"),
            makeNetwork(id: "c", band: .band6, generation: .mode11be, security: "Open"),
        ]
        let coverage = ProtocolAnalyzer.coverage(for: networks)

        XCTAssertEqual(coverage.networkCount, 3)
        XCTAssertEqual(coverage.bandCounts["2.4GHz"], 1)
        XCTAssertEqual(coverage.bandCounts["5GHz"], 1)
        XCTAssertEqual(coverage.bandCounts["6GHz"], 1)
        XCTAssertEqual(coverage.sixGHzCount, 1)
        XCTAssertEqual(coverage.wiFi7Count, 1)
        XCTAssertEqual(coverage.openCount, 1)
        XCTAssertGreaterThanOrEqual(coverage.criticalCount, 1)
    }

    func testEmptyCoverage() {
        let coverage = ProtocolAnalyzer.coverage(for: [])
        XCTAssertEqual(coverage.networkCount, 0)
        XCTAssertTrue(coverage.bandCounts.isEmpty)
        XCTAssertEqual(coverage.securitySummary, "—")
    }
}
