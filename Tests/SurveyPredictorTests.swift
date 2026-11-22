import XCTest

final class SurveyPredictorTests: XCTestCase {
    func testPredictionFallsWithDistance() throws {
        let ap = SurveyAccessPoint.new(x: 0.2, y: 0.5)
        let near = try XCTUnwrap(SurveyPredictor.estimate(x: 0.3, y: 0.5, accessPoints: [ap], walls: [], obstacles: []))
        let far = try XCTUnwrap(SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: []))
        XCTAssertGreaterThan(near, far)
    }

    func testWallMaterialSetsItsTypicalAttenuation() throws {
        XCTAssertLessThan(
            SurveyWallMaterial.drywall.attenuationDb, SurveyWallMaterial.brick.attenuationDb)
        XCTAssertLessThan(
            SurveyWallMaterial.brick.attenuationDb, SurveyWallMaterial.metal.attenuationDb)
        let wall = SurveyWall.new(x1: 0, y1: 0, x2: 0, y2: 1, material: .concrete)
        XCTAssertEqual(wall.material, .concrete)
        XCTAssertEqual(wall.attenuationDb, SurveyWallMaterial.concrete.attenuationDb)
    }

    func testWallWithoutMaterialStillDecodes() throws {
        let json = """
            {"id":"\(UUID().uuidString)","x1":0,"y1":0,"x2":1,"y2":1,"attenuationDb":8}
            """
        let wall = try JSONDecoder().decode(SurveyWall.self, from: Data(json.utf8))
        XCTAssertNil(wall.material)
        XCTAssertEqual(wall.attenuationDb, 8)
    }

    func testAntennaPatternLossGrowsBehindTheBeam() {
        XCTAssertEqual(
            SurveyAntennaPattern.panel.lossDb(bearingDegrees: 10, headingDegrees: 0), 0)
        XCTAssertEqual(
            SurveyAntennaPattern.panel.lossDb(bearingDegrees: 180, headingDegrees: 0),
            SurveyAntennaPattern.panel.backLossDb, accuracy: 0.001)
        XCTAssertGreaterThan(
            SurveyAntennaPattern.directional.lossDb(bearingDegrees: 120, headingDegrees: 0),
            SurveyAntennaPattern.directional.lossDb(bearingDegrees: 0, headingDegrees: 0))
        XCTAssertEqual(
            SurveyAntennaPattern.omni.lossDb(bearingDegrees: 180, headingDegrees: 0), 0)
    }

    func testDirectionalAntennaWeakensTheSideBehindIt() throws {
        let ap = SurveyAccessPoint.new(
            x: 0.5, y: 0.5, pattern: .panel, headingDegrees: 0)
        let front = try XCTUnwrap(
            SurveyPredictor.estimate(
                x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: [],
                planWidthMeters: 30, planHeightMeters: 30))
        let behind = try XCTUnwrap(
            SurveyPredictor.estimate(
                x: 0.2, y: 0.5, accessPoints: [ap], walls: [], obstacles: [],
                planWidthMeters: 30, planHeightMeters: 30))
        XCTAssertGreaterThan(front, behind + 15)
    }

    func testCalibrationUsesTheMedianMeasuredOffset() throws {
        var project = SurveyProject.new(name: "Calibration")
        project.planWidthMeters = 20
        project.planHeightMeters = 20
        project.accessPoints = [
            SurveyAccessPoint.new(x: 0.5, y: 0.5, band: "5GHz", channel: 36)
        ]
        let points = [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)]
        project.samples = points.enumerated().map { index, point in
            let predicted = SurveyPredictor.estimate(
                x: point.0, y: point.1, accessPoints: project.accessPoints,
                walls: [], obstacles: [], planWidthMeters: 20, planHeightMeters: 20)!
            return SurveySample(
                id: UUID(), x: point.0, y: point.1, rssi: predicted + 4 + index,
                ssid: "Calibration", bssid: "AA:BB:CC:DD:EE:FF",
                recordedAt: Date(timeIntervalSince1970: Double(index)))
        }
        let calibration = try XCTUnwrap(SurveyCalibrationCalculator.compute(project: project))
        XCTAssertEqual(calibration.offsetDb, 5.5, accuracy: 0.01)
        XCTAssertEqual(calibration.sampleCount, 4)
        XCTAssertEqual(calibration.residualDb, 1, accuracy: 0.01)
    }

    func testCalibrationNeedsEnoughSamplesAndAccessPoints() {
        var project = SurveyProject.new(name: "Empty")
        XCTAssertNil(SurveyCalibrationCalculator.compute(project: project))
        project.accessPoints = [SurveyAccessPoint.new(x: 0.5, y: 0.5)]
        project.samples = [
            SurveySample(
                id: UUID(), x: 0.2, y: 0.2, rssi: -60, ssid: "X",
                bssid: "AA:BB:CC:DD:EE:FF", recordedAt: Date())
        ]
        XCTAssertNil(SurveyCalibrationCalculator.compute(project: project))
    }

    func testCalibrationOffsetShiftsPrediction() throws {
        let ap = SurveyAccessPoint.new(x: 0.5, y: 0.5)
        let raw = try XCTUnwrap(
            SurveyPredictor.estimate(
                x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: [],
                planWidthMeters: 20, planHeightMeters: 20))
        let calibrated = try XCTUnwrap(
            SurveyPredictor.estimate(
                x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: [],
                planWidthMeters: 20, planHeightMeters: 20, calibrationDb: 4))
        XCTAssertEqual(calibrated, raw + 4)
    }

    func testAccessPointWithoutAntennaFieldsDecodesAsOmni() throws {
        let json = """
            {"id":"\(UUID().uuidString)","x":0.5,"y":0.5,"band":"5GHz",
             "channel":36,"txPowerDbm":20}
            """
        let ap = try JSONDecoder().decode(SurveyAccessPoint.self, from: Data(json.utf8))
        XCTAssertEqual(ap.antennaPattern, .omni)
        XCTAssertEqual(ap.antennaHeading, 0)
    }

    func testFloorAttenuationAffectsThreeDPrediction() throws {
        let floor = SurveyFloorInput(
            floorLevel: 0, floorHeightMeters: 3, walls: [], obstacles: [], accessPoints: [])
        let above = SurveyFloorInput(
            floorLevel: 1, floorHeightMeters: 3, walls: [], obstacles: [],
            accessPoints: [SurveyAccessPoint.new(x: 0.2, y: 0.5)])
        let floors = [floor, above]
        let noLoss = try XCTUnwrap(
            SurveyPredictor.estimate3D(
                x: 0.8, y: 0.5, targetFloorLevel: 0, floors: floors,
                floorAttenuationDb: 0))
        let heavyLoss = try XCTUnwrap(
            SurveyPredictor.estimate3D(
                x: 0.8, y: 0.5, targetFloorLevel: 0, floors: floors,
                floorAttenuationDb: 12))
        XCTAssertGreaterThan(noLoss, heavyLoss)
    }

    func testWallReducesPrediction() throws {
        let ap = SurveyAccessPoint.new(x: 0.2, y: 0.5)
        let wall = SurveyWall.new(x1: 0.5, y1: 0, x2: 0.5, y2: 1)
        let clear = try XCTUnwrap(
            SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [], obstacles: [])
        )
        let blocked = try XCTUnwrap(
            SurveyPredictor.estimate(x: 0.8, y: 0.5, accessPoints: [ap], walls: [wall], obstacles: [])
        )
        XCTAssertLessThan(blocked, clear)
    }
}
