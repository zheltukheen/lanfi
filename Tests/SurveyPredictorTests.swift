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
