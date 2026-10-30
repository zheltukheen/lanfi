import Foundation

/// A single frequency sweep from a hardware spectrum analyzer
/// (RF Explorer over serial, or an imported CSV trace such as a Wi-Spy
/// Chanalyzer export). Amplitudes are dBm, one per frequency step.
struct SpectrumSweep: Equatable {
    let source: String
    let capturedAt: Date
    let startMHz: Double
    let stepMHz: Double
    /// dBm values, `startMHz + index * stepMHz` each.
    let amplitudes: [Double]

    var pointCount: Int { amplitudes.count }
    var spanMHz: Double { stepMHz * Double(max(pointCount - 1, 0)) }
    var endMHz: Double { startMHz + spanMHz }

    func frequencyMHz(at index: Int) -> Double {
        startMHz + stepMHz * Double(index)
    }

    /// Index and value of the strongest sample, if any.
    func peak() -> (index: Int, mhz: Double, dbm: Double)? {
        guard let max = amplitudes.max(), let index = amplitudes.firstIndex(of: max) else { return nil }
        return (index, frequencyMHz(at: index), max)
    }

    /// Element-wise maximum. Returns nil when the grids do not match,
    /// so a max-hold trace never silently mixes different spans.
    func maxHold(with other: SpectrumSweep) -> SpectrumSweep? {
        guard isSameGrid(as: other) else { return nil }
        return SpectrumSweep(
            source: source,
            capturedAt: other.capturedAt,
            startMHz: startMHz,
            stepMHz: stepMHz,
            amplitudes: zip(amplitudes, other.amplitudes).map(max)
        )
    }

    func isSameGrid(as other: SpectrumSweep) -> Bool {
        abs(startMHz - other.startMHz) < 0.001
            && abs(stepMHz - other.stepMHz) < 0.000001
            && pointCount == other.pointCount
    }
}
