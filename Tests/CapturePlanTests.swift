import XCTest

final class CapturePlanTests: XCTestCase {
    func testChannelPlanHopsInOrderAndWraps() {
        let plan = CaptureChannelPlan(channels: [36, 40, 44], dwellMilliseconds: 100)
        XCTAssertTrue(plan.isHopping)
        XCTAssertEqual(plan.channel(atElapsed: 0)?.channel, 36)
        XCTAssertEqual(plan.channel(atElapsed: 0.1)?.channel, 40)
        XCTAssertEqual(plan.channel(atElapsed: 0.25)?.channel, 44)
        XCTAssertEqual(plan.channel(atElapsed: 0.3)?.channel, 36)
        XCTAssertEqual(plan.cycleSeconds, 0.3, accuracy: 0.001)
    }

    func testSingleChannelPlanDoesNotHop() {
        let plan = CaptureChannelPlan(channels: [6], dwellMilliseconds: 150)
        XCTAssertFalse(plan.isHopping)
        XCTAssertEqual(plan.channel(atElapsed: 12)?.channel, 6)
    }

    func testPlanDropsInvalidChannelsAndClampsDwell() {
        let plan = CaptureChannelPlan(channels: [0, 1, 1, 300, 6], dwellMilliseconds: 1)
        XCTAssertEqual(plan.channels.map(\.channel), [1, 6])
        XCTAssertEqual(plan.dwellMilliseconds, CaptureChannelPlan.minimumDwellMilliseconds)
    }

    func testEmptyPlanHasNoChannel() {
        XCTAssertNil(CaptureChannelPlan(channels: [Int]()).channel(atElapsed: 1))
    }

    func testBandIsKeptWithTheChannelNumber() {
        let plan = CaptureChannelPlan(channels: [
            CaptureChannelRef(band: .band6, channel: 5),
            CaptureChannelRef(band: .band24, channel: 5),
        ])
        XCTAssertEqual(plan.channels.count, 2)
        XCTAssertEqual(plan.channels[0].band, .band6)
        XCTAssertEqual(plan.channels[1].band, .band24)
    }

    func testLimitsProduceOnlyTheSizeArgument() {
        let rotating = CaptureLimits(maxFileSizeMB: 50, sliceDataFrameBytes: 128)
        XCTAssertTrue(rotating.rotates)
        XCTAssertTrue(rotating.slicesDataFrames)
        XCTAssertEqual(rotating.tcpdumpArguments, ["-C", "50"])
        XCTAssertEqual(CaptureLimits.none.tcpdumpArguments, [])
        XCTAssertFalse(CaptureLimits.none.rotates)
        XCTAssertFalse(CaptureLimits(maxFileSizeMB: 0, sliceDataFrameBytes: 0).rotates)
    }

    func testPreferredOnlyKeepsJustThePSCChannels() {
        let available = [
            SupportedChannel(band: .band6, channel: 5),
            SupportedChannel(band: .band6, channel: 6),
            SupportedChannel(band: .band5, channel: 36),
        ]
        let all = CaptureProfile.channels(for: [.band6], available: available)
        XCTAssertEqual(all, [5, 6])
        let preferred = CaptureProfile.channels(
            for: [.band6], available: available, pscOnly: true)
        XCTAssertEqual(preferred, [5])
        // PSC filtering never drops channels from other bands.
        let mixed = CaptureProfile.channels(
            for: [.band6, .band5], available: available, pscOnly: true)
        XCTAssertEqual(mixed, [5, 36])
    }
}
