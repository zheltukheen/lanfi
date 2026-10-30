import Foundation

/// Continuous heatmap colour ramp from red (weak) through orange and
/// yellow to green (strong). Pure functions only, so the mapping is
/// unit-testable without SwiftUI.
enum HeatPalette {
    /// Range the ramp spans, in dBm.
    static let range: ClosedRange<Double> = -90...(-40)

    /// RGB components in 0...1 for an RSSI value; values outside the range
    /// clamp to the nearest end of the ramp.
    static func rgb(_ rssi: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max((rssi - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        // Four anchor stops: red → orange → yellow → green.
        return interpolate(t: t)
    }

    /// 0 → red (-90 dBm), 0.5 → yellow (-65 dBm), 1 → green (-40 dBm).
    static func interpolate(t rawT: Double) -> (r: Double, g: Double, b: Double) {
        let t = min(max(rawT, 0), 1)
        let stops: [(Double, (Double, Double, Double))] = [
            (0.00, (0.85, 0.16, 0.12)),  // red
            (0.33, (0.95, 0.55, 0.10)),  // orange
            (0.50, (0.93, 0.82, 0.15)),  // yellow
            (1.00, (0.18, 0.85, 0.35)),  // green
        ]
        for index in stops.indices.dropLast() {
            let (t0, c0) = stops[index]
            let (t1, c1) = stops[index + 1]
            if t >= t0, t <= t1 {
                let local = (t - t0) / (t1 - t0)
                return (
                    r: c0.0 + (c1.0 - c0.0) * local,
                    g: c0.1 + (c1.1 - c0.1) * local,
                    b: c0.2 + (c1.2 - c0.2) * local
                )
            }
        }
        return (r: stops.last!.1.0, g: stops.last!.1.1, b: stops.last!.1.2)
    }
}

/// Memoises the interpolated survey heat grid so hover redraws and layout
/// passes never re-run IDW over every cell. The grid is recomputed only
/// when the input fingerprint or the cell dimensions change.
final class HeatGridCache: ObservableObject {
    struct Grid {
        let columns: Int
        let rows: Int
        /// Row-major RSSI per cell; nil marks cells with no usable sample.
        let cells: [Int?]
    }

    private var storedKey: String = ""
    private var storedGrid: Grid?

    func grid(
        columns: Int,
        rows: Int,
        key: String,
        compute: (_ column: Int, _ row: Int) -> Int?
    ) -> Grid {
        if let storedGrid, storedKey == key,
            storedGrid.columns == columns, storedGrid.rows == rows
        {
            return storedGrid
        }
        var cells = [Int?](repeating: nil, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                cells[row * columns + column] = compute(column, row)
            }
        }
        let grid = Grid(columns: columns, rows: rows, cells: cells)
        storedGrid = grid
        storedKey = key
        return grid
    }

    func invalidate() {
        storedKey = ""
        storedGrid = nil
    }
}
