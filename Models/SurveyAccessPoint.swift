import Foundation

struct SurveyAccessPoint: Codable, Identifiable, Equatable {
    let id: UUID
    var x: Double
    var y: Double
    var band: String
    var channel: Int
    var txPowerDbm: Double

    static func new(x: Double, y: Double, band: String = "5GHz", channel: Int = 36, txPowerDbm: Double = 20)
        -> SurveyAccessPoint
    {
        SurveyAccessPoint(id: UUID(), x: x, y: y, band: band, channel: channel, txPowerDbm: txPowerDbm)
    }
}

struct SurveyFloorInput {
    let floorLevel: Int
    let floorHeightMeters: Double
    let walls: [SurveyWall]
    let obstacles: [SurveyObstacle]
    let accessPoints: [SurveyAccessPoint]
}

enum SurveyPredictor {
    static func estimate3D(
        x: Double, y: Double, targetFloorLevel: Int, floors: [SurveyFloorInput], planWidthMeters: Double = 30
    ) -> Int? {
        var strongest: Int?
        for floor in floors {
            for ap in floor.accessPoints {
                let horizontal = hypot(ap.x - x, ap.y - y) * planWidthMeters
                let vertical = Double(abs(floor.floorLevel - targetFloorLevel)) * floor.floorHeightMeters
                let distance = max(0.3, hypot(horizontal, vertical))
                let frequency = frequencyMHz(band: ap.band, channel: ap.channel)
                let fspl = 20 * log10(distance) + 20 * log10(frequency) - 27.55
                let floorLoss = Double(abs(floor.floorLevel - targetFloorLevel)) * 12.0
                let wallLoss =
                    floors.first(where: { $0.floorLevel == targetFloorLevel })?.walls.reduce(0.0) {
                        total, wall in
                        let hit = SurveyInterpolator.segmentsIntersect(
                            x1: ap.x, y1: ap.y, x2: x, y2: y,
                            x3: wall.x1, y3: wall.y1, x4: wall.x2, y4: wall.y2
                        )
                        return total + (hit ? wall.attenuationDb : 0)
                    } ?? 0
                let rssi = Int((ap.txPowerDbm - fspl - floorLoss - wallLoss).rounded())
                strongest = max(strongest ?? rssi, rssi)
            }
        }
        return strongest
    }

    static func estimate(
        x: Double, y: Double, accessPoints: [SurveyAccessPoint],
        walls: [SurveyWall], obstacles: [SurveyObstacle], planWidthMeters: Double = 30
    ) -> Int? {
        guard !accessPoints.isEmpty else { return nil }
        var strongest: Int?
        for ap in accessPoints {
            let dx = (ap.x - x) * planWidthMeters
            let dy = (ap.y - y) * planWidthMeters
            let distance = max(0.3, sqrt(dx * dx + dy * dy))
            let frequency = frequencyMHz(band: ap.band, channel: ap.channel)
            let fspl = 20 * log10(distance) + 20 * log10(frequency) - 27.55
            let attenuation =
                walls.reduce(0.0) { total, wall in
                    let hit = SurveyInterpolator.segmentsIntersect(
                        x1: ap.x, y1: ap.y, x2: x, y2: y,
                        x3: wall.x1, y3: wall.y1, x4: wall.x2, y4: wall.y2
                    )
                    return total + (hit ? wall.attenuationDb : 0)
                }
                + obstacles.reduce(0.0) { total, obstacle in
                    guard obstacle.points.count >= 3 else { return total }
                    let hit = obstacle.points.indices.contains { index in
                        let next = obstacle.points[(index + 1) % obstacle.points.count]
                        return SurveyInterpolator.segmentsIntersect(
                            x1: ap.x, y1: ap.y, x2: x, y2: y,
                            x3: obstacle.points[index].x, y3: obstacle.points[index].y,
                            x4: next.x, y4: next.y
                        )
                    }
                    return total + (hit ? obstacle.attenuationDb : 0)
                }
            let rssi = Int((ap.txPowerDbm - fspl - attenuation).rounded())
            strongest = max(strongest ?? rssi, rssi)
        }
        return strongest
    }

    static func frequencyMHz(band: String, channel: Int) -> Double {
        if band.contains("2.4") { return 2400 + Double(channel) * 5 }
        if band.contains("6") { return 5950 + Double(channel) * 5 }
        return 5000 + Double(channel) * 5
    }
}
