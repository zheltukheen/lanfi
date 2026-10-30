import XCTest

final class SpectrumSweepTests: XCTestCase {
    private func sweep(
        start: Double = 2400, step: Double = 0.05,
        values: [Double] = [-90, -70, -50]
    ) -> SpectrumSweep {
        SpectrumSweep(
            source: "test", capturedAt: Date(timeIntervalSince1970: 0),
            startMHz: start, stepMHz: step, amplitudes: values
        )
    }

    func testFrequencyMath() {
        let sweep = sweep()
        XCTAssertEqual(sweep.pointCount, 3)
        XCTAssertEqual(sweep.frequencyMHz(at: 0), 2400.0, accuracy: 0.0001)
        XCTAssertEqual(sweep.frequencyMHz(at: 2), 2400.1, accuracy: 0.0001)
        XCTAssertEqual(sweep.endMHz, 2400.1, accuracy: 0.0001)
        XCTAssertEqual(sweep.spanMHz, 0.1, accuracy: 0.0001)
    }

    func testPeak() {
        let peak = sweep().peak()
        XCTAssertEqual(peak?.index, 2)
        XCTAssertEqual(peak?.mhz ?? 0, 2400.1, accuracy: 0.0001)
        XCTAssertEqual(peak?.dbm ?? 0, -50, accuracy: 0.001)
        XCTAssertNil(sweep(values: []).peak())
    }

    func testMaxHoldMergesMatchingGrid() {
        let a = sweep(values: [-90, -70, -50])
        let b = sweep(values: [-60, -80, -40])
        let hold = a.maxHold(with: b)
        XCTAssertEqual(hold?.amplitudes, [-60.0, -70.0, -40.0])
    }

    func testMaxHoldRejectsDifferentGrid() {
        let a = sweep()
        let otherStep = sweep(step: 0.1)
        let otherStart = sweep(start: 2410)
        let otherCount = sweep(values: [-90, -70])
        XCTAssertNil(a.maxHold(with: otherStep))
        XCTAssertNil(a.maxHold(with: otherStart))
        XCTAssertNil(a.maxHold(with: otherCount))
    }
}
