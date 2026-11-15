import Foundation

/// Immutable snapshot of everything the survey heatmap needs. Building a grid
/// can take tens of milliseconds on a dense plan, so the request is copied to a
/// background task and the view only publishes the finished grid.
struct SurveyHeatmapRequest {
    let columns: Int
    let rows: Int
    let cellSize: Double
    let pixelWidth: Double
    let pixelHeight: Double
    let samples: [SurveySample]
    let walls: [SurveyWall]
    let obstacles: [SurveyObstacle]
    let accessPoints: [SurveyAccessPoint]
    let predictiveMode: Bool
    let planWidthMeters: Double

    var key: String {
        var parts = [
            "\(columns)x\(rows)",
            "pixel:\(pixelWidth)x\(pixelHeight)",
            "cell:\(cellSize)",
            predictiveMode ? "predictive" : "measured",
        ]
        for sample in samples {
            parts.append("s:\(sample.id.uuidString):\(sample.x):\(sample.y):\(sample.rssi)")
        }
        for wall in walls {
            parts.append("w:\(wall.id.uuidString):\(wall.x1):\(wall.y1):\(wall.x2):\(wall.y2):\(wall.attenuationDb)")
        }
        for obstacle in obstacles {
            parts.append("o:\(obstacle.id.uuidString):\(obstacle.attenuationDb)")
            for point in obstacle.points {
                parts.append("\(point.x):\(point.y)")
            }
        }
        for ap in accessPoints {
            parts.append("a:\(ap.id.uuidString):\(ap.x):\(ap.y):\(ap.band):\(ap.channel):\(ap.txPowerDbm)")
        }
        parts.append("plan:\(planWidthMeters)")
        return parts.joined(separator: "|")
    }

    /// Yields the grid after every `chunkRows` rows, then a final complete
    /// grid. The view can paint the first rows while the rest is computed.
    func stream(chunkRows: Int = 16) -> AsyncStream<HeatGridCache.Grid> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var cells = [Int?](repeating: nil, count: max(0, columns * rows))
                guard columns > 0, rows > 0, pixelWidth > 0, pixelHeight > 0 else {
                    continuation.yield(
                        HeatGridCache.Grid(columns: columns, rows: rows, cells: cells))
                    continuation.finish()
                    return
                }

                let chunk = max(1, chunkRows)
                for row in 0..<rows {
                    if Task.isCancelled { break }
                    let ny = (Double(row) * cellSize + cellSize / 2) / pixelHeight
                    for column in 0..<columns {
                        let nx = (Double(column) * cellSize + cellSize / 2) / pixelWidth
                        cells[row * columns + column] = estimate(nx: nx, ny: ny)
                    }
                    if (row + 1) % chunk == 0 {
                        continuation.yield(
                            HeatGridCache.Grid(columns: columns, rows: rows, cells: cells))
                    }
                }
                continuation.yield(
                    HeatGridCache.Grid(columns: columns, rows: rows, cells: cells))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func build() -> HeatGridCache.Grid {
        var cells = [Int?](repeating: nil, count: columns * rows)
        guard columns > 0, rows > 0, pixelWidth > 0, pixelHeight > 0 else {
            return HeatGridCache.Grid(columns: columns, rows: rows, cells: cells)
        }

        for row in 0..<rows {
            let ny = (Double(row) * cellSize + cellSize / 2) / pixelHeight
            for column in 0..<columns {
                let nx = (Double(column) * cellSize + cellSize / 2) / pixelWidth
                cells[row * columns + column] = estimate(nx: nx, ny: ny)
            }
        }
        return HeatGridCache.Grid(columns: columns, rows: rows, cells: cells)
    }

    private func estimate(nx: Double, ny: Double) -> Int? {
        if predictiveMode && !accessPoints.isEmpty {
            return SurveyPredictor.estimate(
                x: nx, y: ny, accessPoints: accessPoints, walls: walls,
                obstacles: obstacles, planWidthMeters: planWidthMeters)
        }
        guard !samples.isEmpty else { return nil }
        return SurveyInterpolator.estimate(
            x: nx, y: ny, samples: samples, walls: walls, obstacles: obstacles)
    }
}
