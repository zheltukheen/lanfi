import Foundation
import XCTest

final class GPSTripTests: XCTestCase {
    private let point = GeoPoint(latitude: 51.5075, longitude: -0.1278)

    func testStrongestObservationWinsPerBSSID() {
        var trip = GPSTrip(name: "Office")
        trip.record(
            bssid: "AA:BB:CC:DD:EE:01", ssid: "Office", rssi: -70, isOpen: false,
            band: "5GHz", channel: 36, at: point)
        let second = GeoPoint(latitude: 51.5076, longitude: -0.1279)
        trip.record(
            bssid: "aa:bb:cc:dd:ee:01", ssid: "Office", rssi: -55, isOpen: false,
            band: "5GHz", channel: 36, at: second)
        trip.record(
            bssid: "AA:BB:CC:DD:EE:01", ssid: "Office", rssi: -80, isOpen: false,
            band: "5GHz", channel: 36, at: point)

        XCTAssertEqual(trip.pins.count, 1)
        XCTAssertEqual(trip.pins.first?.rssi, -55)
        XCTAssertEqual(trip.pins.first?.latitude ?? 0, second.latitude, accuracy: 0.000001)
        XCTAssertEqual(trip.track.count, 3)
    }

    func testOpenAndSecuredCounts() {
        var trip = GPSTrip(name: "Cafe")
        trip.record(
            bssid: "1", ssid: "Guest", rssi: -60, isOpen: true, band: "2.4GHz",
            channel: 6, at: point)
        trip.record(
            bssid: "2", ssid: "Home", rssi: -50, isOpen: false, band: "5GHz",
            channel: 44, at: point)
        XCTAssertEqual(trip.openCount, 1)
        XCTAssertEqual(trip.securedCount, 1)
    }

    func testGeoJSONHasPointPerNetworkAndTrackLine() throws {
        var trip = GPSTrip(name: "Walk")
        trip.record(
            bssid: "AA:BB", ssid: "One", rssi: -61, isOpen: true, band: "2.4GHz",
            channel: 1, at: point)
        trip.record(
            bssid: "AA:BB", ssid: "One", rssi: -62, isOpen: true, band: "2.4GHz",
            channel: 1, at: GeoPoint(latitude: 51.5077, longitude: -0.1280))
        let text = GPSTripExport.geoJSON(trip)
        let data = try XCTUnwrap(text.data(using: .utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        let features = try XCTUnwrap(object["features"] as? [[String: Any]])
        XCTAssertEqual(features.count, 2)
        let pointFeature = try XCTUnwrap(features.first)
        let geometry = try XCTUnwrap(pointFeature["geometry"] as? [String: Any])
        XCTAssertEqual(geometry["type"] as? String, "Point")
        let properties = try XCTUnwrap(pointFeature["properties"] as? [String: Any])
        XCTAssertEqual(properties["bssid"] as? String, "AA:BB")
        XCTAssertEqual(properties["security"] as? String, "open")
    }

    func testCSVEscapesAndCarriesEveryPin() {
        var trip = GPSTrip(name: "Walk")
        trip.record(
            bssid: "AA:BB", ssid: "Cafe, Guest", rssi: -61, isOpen: true,
            band: "2.4GHz", channel: 1, at: point)
        let lines = GPSTripExport.csv(trip).split(separator: "\n")
        XCTAssertEqual(lines.first, "ssid,bssid,latitude,longitude,rssi_dbm,security,band,channel,seen_at")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("\"Cafe, Guest\""))
        XCTAssertTrue(lines[1].contains("open"))
    }

    func testStoreRoundTripsNamedTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GPSTripStore(url: directory.appendingPathComponent("gps-trips.json"))
        var trip = GPSTrip(name: "Home")
        trip.record(
            bssid: "AA:BB", ssid: "Home", rssi: -50, isOpen: false, band: "5GHz",
            channel: 36, at: point)
        try store.save([trip])
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Home")
        XCTAssertEqual(loaded.first?.pins.first?.bssid, "AA:BB")
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
final class GPSTripRecorderTests: XCTestCase {
    func testRecordsOnlyWhileStartedAndStopsOnStop() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GPSTripStore(url: directory.appendingPathComponent("gps-trips.json"))
        let recorder = GPSTripRecorder(store: store, sampleInterval: 3600)
        let point = GeoPoint(latitude: 51.5, longitude: -0.12)
        recorder.location = { point }
        recorder.networks = {
            [
                makeNetwork(
                    bssid: "AA:BB:CC:DD:EE:01", ssid: "Office", band: .band5,
                    channel: 36, security: "WPA2", signal: -58)
            ]
        }
        XCTAssertTrue(recorder.trips.isEmpty)

        recorder.start(name: "Test walk")
        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.trips.first?.pins.count, 1)
        recorder.stop()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNotNil(recorder.trips.first?.endedAt)

        recorder.sampleNow()
        XCTAssertEqual(recorder.trips.first?.pins.count, 1, "stopped recorder adds nothing")
        try? FileManager.default.removeItem(at: directory)
    }
}
