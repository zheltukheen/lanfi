import Foundation

/// Antenna shape used by the predictive planner. Omni is the default; the
/// directional presets are modelled as a beam with extra loss outside it, so a
/// wall-mounted panel behind a partition does not paint coverage through it.
enum SurveyAntennaPattern: String, CaseIterable, Identifiable, Codable {
    case omni
    case directional
    case panel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .omni: return String(localized: "Omni")
        case .directional: return String(localized: "Directional 90°")
        case .panel: return String(localized: "Panel 60°")
        }
    }

    var beamwidthDegrees: Double {
        switch self {
        case .omni: return 360
        case .directional: return 90
        case .panel: return 60
        }
    }

    /// Loss straight behind the antenna, relative to the main lobe.
    var backLossDb: Double {
        switch self {
        case .omni: return 0
        case .directional: return 15
        case .panel: return 20
        }
    }

    /// Extra loss for a bearing away from the antenna heading. The main lobe is
    /// flat, then loss grows smoothly to `backLossDb` at the rear.
    func lossDb(bearingDegrees: Double, headingDegrees: Double) -> Double {
        guard self != .omni else { return 0 }
        var difference = abs(bearingDegrees - headingDegrees).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference = 360 - difference }
        let half = beamwidthDegrees / 2
        guard difference > half else { return 0 }
        let outside = (difference - half) / max(1, 180 - half)
        // Smooth the edge so a cell just outside the beam is not a cliff.
        return backLossDb * (0.5 - 0.5 * cos(outside * .pi))
    }
}

struct SurveyAccessPoint: Codable, Identifiable, Equatable {
    let id: UUID
    var x: Double
    var y: Double
    var band: String
    var channel: Int
    var txPowerDbm: Double
    /// Optional so surveys written before antenna patterns decode as omni.
    var pattern: SurveyAntennaPattern? = nil
    /// Compass-style heading in degrees: 0° points along +X (east).
    var headingDegrees: Double? = nil

    static func new(
        x: Double, y: Double, band: String = "5GHz", channel: Int = 36,
        txPowerDbm: Double = 20, pattern: SurveyAntennaPattern = .omni,
        headingDegrees: Double = 0
    ) -> SurveyAccessPoint {
        SurveyAccessPoint(
            id: UUID(), x: x, y: y, band: band, channel: channel, txPowerDbm: txPowerDbm,
            pattern: pattern, headingDegrees: headingDegrees)
    }

    var antennaPattern: SurveyAntennaPattern { pattern ?? .omni }
    var antennaHeading: Double { headingDegrees ?? 0 }

    /// Bearing from the AP to a point, in the same convention as the heading.
    func bearingDegrees(toX x: Double, y: Double, planWidthMeters: Double, planHeightMeters: Double)
        -> Double
    {
        let dx = (x - self.x) * planWidthMeters
        let dy = (y - self.y) * planHeightMeters
        guard dx != 0 || dy != 0 else { return 0 }
        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    func antennaLossDb(
        toX x: Double, y: Double, planWidthMeters: Double, planHeightMeters: Double
    ) -> Double {
        guard antennaPattern != .omni else { return 0 }
        let bearing = bearingDegrees(
            toX: x, y: y, planWidthMeters: planWidthMeters,
            planHeightMeters: planHeightMeters)
        return antennaPattern.lossDb(
            bearingDegrees: bearing, headingDegrees: antennaHeading)
    }
}

struct SurveyFloorInput {
    let floorLevel: Int
    let floorHeightMeters: Double
    let walls: [SurveyWall]
    let obstacles: [SurveyObstacle]
    let accessPoints: [SurveyAccessPoint]
    var cutouts: [SurveyCutout] = []
}

enum SurveyPredictor {
    static func estimate3D(
        x: Double, y: Double, targetFloorLevel: Int, floors: [SurveyFloorInput],
        planWidthMeters: Double = 30, floorAttenuationDb: Double = 12,
        calibrationDb: Double = 0
    ) -> Int? {
        if let target = floors.first(where: { $0.floorLevel == targetFloorLevel }),
            target.cutouts.contains(where: { $0.contains(x: x, y: y) })
        {
            return nil
        }
        var strongest: Int?
        for floor in floors {
            for ap in floor.accessPoints {
                let horizontal = hypot(ap.x - x, ap.y - y) * planWidthMeters
                let vertical = Double(abs(floor.floorLevel - targetFloorLevel)) * floor.floorHeightMeters
                let distance = max(0.3, hypot(horizontal, vertical))
                let frequency = frequencyMHz(band: ap.band, channel: ap.channel)
                let fspl = 20 * log10(distance) + 20 * log10(frequency) - 27.55
                let floorLoss =
                    Double(abs(floor.floorLevel - targetFloorLevel)) * floorAttenuationDb
                let wallLoss =
                    floors.first(where: { $0.floorLevel == targetFloorLevel })?.walls.reduce(0.0) {
                        total, wall in
                        let hit = SurveyInterpolator.segmentsIntersect(
                            x1: ap.x, y1: ap.y, x2: x, y2: y,
                            x3: wall.x1, y3: wall.y1, x4: wall.x2, y4: wall.y2
                        )
                        return total + (hit ? wall.attenuationDb : 0)
                    } ?? 0
                let antennaLoss = ap.antennaLossDb(
                    toX: x, y: y, planWidthMeters: planWidthMeters,
                    planHeightMeters: planWidthMeters)
                let rssi = Int(
                    (ap.txPowerDbm - fspl - floorLoss - wallLoss - antennaLoss + calibrationDb)
                        .rounded())
                strongest = max(strongest ?? rssi, rssi)
            }
        }
        return strongest
    }

    /// `planHeightMeters` keeps the distance honest when the plan is drawn
    /// stretched across a workspace whose aspect ratio differs from the plan's:
    /// a metre on X and a metre on Y are then a different number of points.
    static func estimate(
        x: Double, y: Double, accessPoints: [SurveyAccessPoint],
        walls: [SurveyWall], obstacles: [SurveyObstacle], planWidthMeters: Double = 30,
        planHeightMeters: Double? = nil, calibrationDb: Double = 0,
        cutouts: [SurveyCutout] = []
    ) -> Int? {
        guard !accessPoints.isEmpty else { return nil }
        guard !cutouts.contains(where: { $0.contains(x: x, y: y) }) else { return nil }
        let heightMeters = planHeightMeters ?? planWidthMeters
        var strongest: Int?
        for ap in accessPoints {
            let dx = (ap.x - x) * planWidthMeters
            let dy = (ap.y - y) * heightMeters
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
            let antennaLoss = ap.antennaLossDb(
                toX: x, y: y, planWidthMeters: planWidthMeters,
                planHeightMeters: heightMeters)
            let rssi = Int(
                (ap.txPowerDbm - fspl - attenuation - antennaLoss + calibrationDb).rounded())
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
