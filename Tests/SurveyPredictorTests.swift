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
