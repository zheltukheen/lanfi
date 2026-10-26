import Foundation

/// Inverse-distance-weighted RSSI interpolation with simple wall attenuation.
/// Coordinates are normalised to the floor-plan rect (0...1).
enum SurveyInterpolator {
    static func estimate(
        x: Double,
        y: Double,
        samples: [SurveySample],
        walls: [SurveyWall],
        obstacles: [SurveyObstacle] = [],
        power: Double = 2.0
    ) -> Int? {
        guard !samples.isEmpty else { return nil }
        var weighted = 0.0
        var totalWeight = 0.0
        for sample in samples {
            let dx = sample.x - x
            let dy = sample.y - y
            let distance = max(0.0001, sqrt(dx * dx + dy * dy))
            if distance > 0.9 { continue }
            let wallAttenuation = walls.reduce(0.0) { total, wall in
                let wallHit = segmentsIntersect(
                    x1: sample.x, y1: sample.y, x2: x, y2: y,
                    x3: wall.x1, y3: wall.y1, x4: wall.x2, y4: wall.y2
                )
                return total + (wallHit ? wall.attenuationDb : 0)
            }
            let obstacleAttenuation = obstacles.reduce(0.0) { total, obstacle in
                guard let boundary = polygonCrossed(obstacle.points, sx: sample.x, sy: sample.y, ex: x, ey: y)
                else { return total }
                return total + (boundary ? obstacle.attenuationDb : 0)
            }
            let attenuation = wallAttenuation + obstacleAttenuation
            let value = Double(sample.rssi) - attenuation
            let weight = 1.0 / pow(distance, power)
            weighted += value * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return Int((weighted / totalWeight).rounded())
    }

    private static func polygonCrossed(
        _ points: [SurveyPoint], sx: Double, sy: Double, ex: Double, ey: Double
    ) -> Bool? {
        guard points.count >= 3 else { return nil }
        var crossings = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            if segmentsIntersect(
                x1: sx, y1: sy, x2: ex, y2: ey,
                x3: points[index].x, y3: points[index].y, x4: next.x, y4: next.y
            ) {
                crossings += 1
            }
        }
        return crossings > 0
    }

    static func wallAttenuation(for wall: SurveyWall) -> Double {
        wall.attenuationDb
    }

    static func segmentsIntersect(
        x1: Double, y1: Double, x2: Double, y2: Double,
        x3: Double, y3: Double, x4: Double, y4: Double
    ) -> Bool {
        func orientation(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ cx: Double, _ cy: Double)
            -> Double
        {
            (by - ay) * (cx - bx) - (bx - ax) * (cy - by)
        }
        let o1 = orientation(x1, y1, x2, y2, x3, y3)
        let o2 = orientation(x1, y1, x2, y2, x4, y4)
        let o3 = orientation(x3, y3, x4, y4, x1, y1)
        let o4 = orientation(x3, y3, x4, y4, x2, y2)
        return o1 * o2 < 0 && o3 * o4 < 0
    }
}
