import XCTest

final class ScanModePlanTests: XCTestCase {
    private let wifi = ScanHardwareProfile(
        machineIdentifier: "Mac16,1", cpuBrand: "Apple M4", interfaceNames: ["en0"])
    private let appleN1 = ScanHardwareProfile(
        machineIdentifier: "Mac17,1", cpuBrand: "Apple M5 Pro", interfaceNames: ["en0"])

    private func channels(_ pairs: [(WiFiBand, Int)]) -> [SupportedChannel] {
        pairs.map { SupportedChannel(band: $0.0, channel: $0.1) }
    }

    // MARK: - Channel planning

    func testPassivePlanPutsSixGHzPSCFirstAndKeepsNonPSC() {
        let supported = channels([
            (.band6, 1), (.band6, 5), (.band6, 37), (.band5, 36), (.band24, 6),
        ])

        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, profile: wifi)

        XCTAssertEqual(plan.items.count, 5)
        let sixGHz = plan.items.filter { $0.band == .band6 }
        XCTAssertEqual(sixGHz.map(\.channel), [5, 37, 1])
        XCTAssertTrue(sixGHz[0].isPrimaryScanningChannel)
        XCTAssertTrue(sixGHz[1].isPrimaryScanningChannel)
        XCTAssertFalse(sixGHz[2].isPrimaryScanningChannel)
        XCTAssertEqual(plan.sixGHzNonPreferredCount, 1)
        XCTAssertTrue(plan.warnings.contains { $0.contains("non-PSC") || $0.contains("PSC") })
    }

    func testNeighborReportedChannelsLeadTheirBand() {
        let supported = channels([(.band6, 5), (.band6, 37), (.band6, 69), (.band6, 133)])

        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, neighborChannels: [133], profile: wifi)

        XCTAssertEqual(plan.items.map(\.channel), [133, 5, 37, 69])
        XCTAssertTrue(plan.items[0].isNeighborReported)
    }

    func testDFSAndSixGHzLabels() {
        let supported = channels([(.band5, 36), (.band5, 52), (.band5, 100), (.band6, 5), (.band6, 1)])

        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, profile: wifi)

        let byChannel = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.channel, $0) })
        XCTAssertNil(byChannel[36]?.regulatoryLabel)
        XCTAssertEqual(byChannel[52]?.regulatoryLabel, "DFS")
        XCTAssertTrue(byChannel[52]?.isDFS == true)
        XCTAssertEqual(byChannel[100]?.regulatoryLabel, "DFS")
        XCTAssertEqual(byChannel[5]?.regulatoryLabel, "PSC · LPI/SP")
        XCTAssertEqual(byChannel[1]?.regulatoryLabel, "LPI/SP")
    }

    func testDirectedPlanOnlyContainsSelectedChannels() {
        let supported = channels([(.band24, 1), (.band24, 6), (.band5, 36), (.band6, 37)])

        let plan = ScanChannelPlanner.plan(
            mode: .directed, supported: supported,
            directedChannels: ["3-37", "2-36"], profile: wifi)

        XCTAssertEqual(Set(plan.items.map(\.channel)), [36, 37])
        XCTAssertFalse(plan.warnings.contains { $0.contains("at least one channel") })
    }

    func testDirectedPlanWithoutSelectionWarnsAndIsEmpty() {
        let plan = ScanChannelPlanner.plan(
            mode: .directed, supported: channels([(.band5, 36)]), profile: wifi)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.warnings.contains { $0.contains("at least one channel") })
    }

    func testDwellIsClampedAndTotalsAddUp() {
        let supported = channels([(.band5, 36), (.band5, 40), (.band5, 44)])

        let slow = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, dwellMilliseconds: 5_000, profile: wifi)
        XCTAssertEqual(slow.items.map(\.dwellMilliseconds), [1000, 1000, 1000])
        XCTAssertEqual(slow.totalDuration, 3, accuracy: 0.001)

        let fast = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, dwellMilliseconds: 1, profile: wifi)
        XCTAssertEqual(fast.items.map(\.dwellMilliseconds), [50, 50, 50])
        XCTAssertTrue(fast.warnings.contains { $0.contains("102.4") })
    }

    func testActivePlanCoversEveryChannelWithoutDwell() {
        let supported = channels([(.band24, 1), (.band5, 36), (.band6, 37)])

        let plan = ScanChannelPlanner.plan(
            mode: .active, supported: supported, profile: wifi)

        XCTAssertEqual(plan.items.count, 3)
        XCTAssertEqual(plan.totalDuration, 0)
        XCTAssertTrue(plan.items.allSatisfy { $0.dwellMilliseconds == 0 })
    }

    func testDuplicateAndInvalidChannelsAreDropped() {
        let supported = channels([(.band5, 36), (.band5, 36), (.band5, 0)])

        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, profile: wifi)

        XCTAssertEqual(plan.items.map(\.channel), [36])
    }

    // MARK: - Hardware capabilities

    func testOrdinaryMacSupportsEveryMode() {
        let capabilities = ScanModeCapabilities.evaluate(profile: wifi)

        XCTAssertEqual(capabilities.active, .available)
        XCTAssertEqual(capabilities.passive, .available)
        XCTAssertEqual(capabilities.directed, .available)
    }

    func testAppleN1LimitsPassiveToASingleChannel() {
        let capabilities = ScanModeCapabilities.evaluate(profile: appleN1)

        XCTAssertTrue(capabilities.active.isUsable)
        XCTAssertTrue(capabilities.passive.isUsable)
        XCTAssertTrue(capabilities.passive.isLimited)
        XCTAssertNotNil(capabilities.passive.explanation)
        XCTAssertTrue(capabilities.directed.isUsable)

        let supported = channels([(.band6, 5), (.band6, 37), (.band5, 36)])
        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, profile: appleN1)
        XCTAssertEqual(plan.items.count, 1)
        XCTAssertTrue(plan.warnings.contains { $0.contains("N1") })
    }

    func testWithoutWiFiInterfaceEveryModeIsUnavailable() {
        let capabilities = ScanModeCapabilities.evaluate(profile: .unknown)

        XCTAssertFalse(capabilities.active.isUsable)
        XCTAssertFalse(capabilities.passive.isUsable)
        XCTAssertFalse(capabilities.directed.isUsable)
        XCTAssertEqual(capabilities.directed.badge, "Unavailable")
    }

    // MARK: - Hardware smoke test

    /// Opt-in: `LANFI_HARDWARE_SMOKE=1 xcodebuild test …`. Probes the real
    /// radio (no capture, no authorization) and prints the plan an operator
    /// should see before a manual passive run.
    func testHardwareCapabilitySmoke() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LANFI_HARDWARE_SMOKE"] == "1",
            "Set LANFI_HARDWARE_SMOKE=1 to probe the local Wi-Fi hardware.")

        let profile = ScanHardwareProbe.current()
        let capabilities = ScanModeCapabilities.evaluate(profile: profile)
        let supported = SpectrumCapabilities.current()
        let plan = ScanChannelPlanner.plan(
            mode: .passive, supported: supported, profile: profile)

        print(
            "hardware: \(profile.displayName) interfaces=\(profile.interfaceNames) "
                + "passive=\(capabilities.passive) channels=\(plan.items.count) "
                + "plan=\(plan.summary) duration=\(plan.totalDuration)s")

        if profile.hasWiFiInterface {
            XCTAssertTrue(capabilities.active.isUsable)
            XCTAssertFalse(supported.isEmpty)
        }
    }
}
