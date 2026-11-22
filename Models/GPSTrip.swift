import Foundation

/// One network seen at one position during a GPS walk. The map keeps the
/// strongest observation per BSSID, so walking past the same AP does not pile
/// up duplicates at the edge of its coverage.
struct GPSNetworkPin: Codable, Equatable, Identifiable {
    var bssid: String
    var ssid: String
    var latitude: Double
    var longitude: Double
    var rssi: Int
    var isOpen: Bool
    var band: String
    var channel: Int
    var seenAt: Date

    var id: String { bssid }

    var coordinateLabel: String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }
}

/// A named recording session. Pins and the walked track stay together so a
/// saved trip can be reopened or exported without the live scan.
struct GPSTrip: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let startedAt: Date
    var endedAt: Date?
    var pins: [GPSNetworkPin]
    var track: [GeoPoint]

    init(
        id: UUID = UUID(), name: String, startedAt: Date = Date(),
        endedAt: Date? = nil, pins: [GPSNetworkPin] = [], track: [GeoPoint] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pins = pins
        self.track = track
    }

    var isRecording: Bool { endedAt == nil }

    var openCount: Int { pins.filter(\.isOpen).count }
    var securedCount: Int { pins.count - openCount }

    /// Records the observation at `point`. The track is appended when the walk
    /// moved more than a metre; the pin is replaced only by a stronger signal.
    mutating func record(
        bssid: String, ssid: String, rssi: Int, isOpen: Bool, band: String,
        channel: Int, at point: GeoPoint, now: Date = Date()
    ) {
        if let last = track.last, GeoMath.distanceMeters(last, point) < 1 {
            // Same spot; a repeated sample adds nothing to the track.
        } else {
            track.append(point)
        }
        if let index = pins.firstIndex(where: { $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame }) {
            guard rssi > pins[index].rssi else { return }
            pins[index].ssid = ssid
            pins[index].latitude = point.latitude
            pins[index].longitude = point.longitude
            pins[index].rssi = rssi
            pins[index].isOpen = isOpen
            pins[index].band = band
            pins[index].channel = channel
            pins[index].seenAt = now
        } else {
            pins.append(
                GPSNetworkPin(
                    bssid: bssid, ssid: ssid, latitude: point.latitude,
                    longitude: point.longitude, rssi: rssi, isOpen: isOpen,
                    band: band, channel: channel, seenAt: now))
        }
    }
}

/// GeoJSON and CSV are the two formats the roadmap promises: GeoJSON opens in
/// mapping tools, CSV opens in a spreadsheet.
enum GPSTripExport {
    static func geoJSON(_ trip: GPSTrip) -> String {
        var features: [[String: Any]] = []
        for pin in trip.pins {
            features.append([
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [pin.longitude, pin.latitude],
                ],
                "properties": [
                    "bssid": pin.bssid,
                    "ssid": pin.ssid,
                    "rssi": pin.rssi,
                    "security": pin.isOpen ? "open" : "secured",
                    "band": pin.band,
                    "channel": pin.channel,
                    "seenAt": ISO8601DateFormatter().string(from: pin.seenAt),
                ],
            ])
        }
        if trip.track.count > 1 {
            features.append([
                "type": "Feature",
                "geometry": [
                    "type": "LineString",
                    "coordinates": trip.track.map { [$0.longitude, $0.latitude] },
                ],
                "properties": ["name": trip.name, "kind": "track"],
            ])
        }
        let object: [String: Any] = [
            "type": "FeatureCollection",
            "name": trip.name,
            "features": features,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return "{\"type\":\"FeatureCollection\",\"features\":[]}" }
        return text
    }

    static func csv(_ trip: GPSTrip) -> String {
        let header =
            "ssid,bssid,latitude,longitude,rssi_dbm,security,band,channel,seen_at"
        let rows = trip.pins.map { pin in
            [
                escape(pin.ssid), escape(pin.bssid),
                String(format: "%.6f", pin.latitude),
                String(format: "%.6f", pin.longitude),
                "\(pin.rssi)", pin.isOpen ? "open" : "secured",
                escape(pin.band), "\(pin.channel)",
                ISO8601DateFormatter().string(from: pin.seenAt),
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Named trips persist as one JSON file in Application Support. The store is
/// injected in tests so nothing touches the real support folder.
struct GPSTripStore {
    let url: URL

    init(url: URL = GPSTripStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return
            support
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("gps-trips.json")
    }

    func load() -> [GPSTrip] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([GPSTrip].self, from: data)) ?? []
    }

    func save(_ trips: [GPSTrip]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(trips).write(to: url, options: .atomic)
    }
}
