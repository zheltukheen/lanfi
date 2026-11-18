import Foundation

/// A WGS-84 position used by GPS-tagged surveys. Optional on samples so old
/// survey files keep decoding.
struct GeoPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
}

/// Minimal GPX 1.1 reader/writer: enough for survey walks exported from phones
/// and watches, without a third-party parser.
enum GPXCodec {
    static func parse(data: Data) -> [GeoPoint] {
        let parser = GPXParserDelegate()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.points
    }

    static func document(points: [GeoPoint], name: String = "LanFi survey") -> String {
        let body =
            points
            .map {
                String(
                    format: "      <trkpt lat=\"%.7f\" lon=\"%.7f\"></trkpt>", $0.latitude,
                    $0.longitude)
            }
            .joined(separator: "\n")
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="LanFi" xmlns="http://www.topografix.com/GPX/1/1">
              <trk>
                <name>\(escape(name))</name>
                <trkseg>
            \(body)
                </trkseg>
              </trk>
            </gpx>
            """
    }

    /// A deterministic demo walk (a loop around a small office block) for the
    /// map when the bundled sample is unavailable.
    static func demoTrack(
        centre: GeoPoint = GeoPoint(latitude: 51.5075, longitude: -0.1278)
    ) -> [GeoPoint] {
        (0..<24).map { index in
            let angle = Double(index) / 24 * 2 * .pi
            let radius = 0.00018 + Double(index % 3) * 0.00002
            return GeoPoint(
                latitude: centre.latitude + sin(angle) * radius,
                longitude: centre.longitude + cos(angle) * radius * 1.6)
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [GeoPoint] = []

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "trkpt" || elementName == "wpt" else { return }
        guard let latitude = Double(attributeDict["lat"] ?? ""),
            let longitude = Double(attributeDict["lon"] ?? "")
        else { return }
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }
        points.append(GeoPoint(latitude: latitude, longitude: longitude))
    }
}

enum GeoMath {
    /// Haversine distance in metres.
    static func distanceMeters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let h =
            sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * radius * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    static func centre(_ points: [GeoPoint]) -> GeoPoint? {
        guard !points.isEmpty else { return nil }
        return GeoPoint(
            latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
            longitude: points.map(\.longitude).reduce(0, +) / Double(points.count)
        )
    }

    static func spanMeters(_ points: [GeoPoint]) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        var total = 0.0
        var previous = first
        for point in points.dropFirst() {
            total += distanceMeters(previous, point)
            previous = point
        }
        if points.count == 1 { return distanceMeters(first, last) }
        return total
    }
}
