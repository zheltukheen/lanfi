import XCTest

@testable import LanFi

final class SurveyGeoTests: XCTestCase {
    private let sampleGPX = """
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="51.5000" lon="-0.1200"/>
            <trkpt lat="51.5002" lon="-0.1201"/>
            <trkpt lat="999" lon="0"/>
          </trkseg></trk>
        </gpx>
        """

    func testParsesValidTrackPointsAndSkipsInvalid() {
        let points = GPXCodec.parse(data: Data(sampleGPX.utf8))
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.first?.latitude ?? 0, 51.5, accuracy: 0.0001)
        XCTAssertEqual(points.last?.longitude ?? 0, -0.1201, accuracy: 0.0001)
    }

    func testRoundTripDocument() {
        let points = [
            GeoPoint(latitude: 51.5, longitude: -0.12),
            GeoPoint(latitude: 51.5002, longitude: -0.1201),
        ]
        let document = GPXCodec.document(points: points, name: "Floor 1")
        let parsed = GPXCodec.parse(data: Data(document.utf8))
        XCTAssertEqual(parsed, points)
        XCTAssertTrue(document.contains("<name>Floor 1</name>"))
    }

    func testDistanceAndSpan() {
        let a = GeoPoint(latitude: 51.5, longitude: -0.12)
        let b = GeoPoint(latitude: 51.5, longitude: -0.121)
        XCTAssertGreaterThan(GeoMath.distanceMeters(a, b), 50)
        XCTAssertLessThan(GeoMath.distanceMeters(a, b), 90)
        XCTAssertEqual(GeoMath.spanMeters([a, b]), GeoMath.distanceMeters(a, b), accuracy: 1)
        XCTAssertEqual(GeoMath.centre([a, b])?.longitude ?? 0, -0.1205, accuracy: 0.0001)
    }
}
