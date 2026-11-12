import Foundation
import Network

struct VisualTracerouteHop: Identifiable, Equatable {
    let hop: TracerouteHop
    let geo: GeoIPReport?

    var id: Int { hop.ttl }

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let geo else { return nil }
        return (geo.latitude, geo.longitude)
    }
}

/// Great-circle leg between two consecutive geolocated hops, so the map can
/// draw the route as hops resolve instead of waiting for the whole trace.
struct VisualRouteLink: Equatable {
    let ttl: Int
    let fromLatitude: Double
    let fromLongitude: Double
    let toLatitude: Double
    let toLongitude: Double
    let milliseconds: Double?
}

enum VisualRouteLatency: Equatable {
    case fast
    case moderate
    case slow
    case unknown

    static func band(for milliseconds: Double?) -> VisualRouteLatency {
        guard let milliseconds else { return .unknown }
        if milliseconds < 40 { return .fast }
        if milliseconds < 120 { return .moderate }
        return .slow
    }
}

enum VisualTraceroutePath {
    /// Consecutive geolocated hops in TTL order. Hops without a location are
    /// skipped, so a private or filtered hop does not break the drawn route.
    static func links(for hops: [VisualTracerouteHop]) -> [VisualRouteLink] {
        let located = hops.filter { $0.geo != nil }.sorted { $0.id < $1.id }
        guard located.count > 1 else { return [] }
        return zip(located, located.dropFirst()).map { current, next in
            VisualRouteLink(
                ttl: next.id,
                fromLatitude: current.geo?.latitude ?? 0,
                fromLongitude: current.geo?.longitude ?? 0,
                toLatitude: next.geo?.latitude ?? 0,
                toLongitude: next.geo?.longitude ?? 0,
                milliseconds: next.hop.averageMilliseconds
            )
        }
    }

    static func links(origin: GeoIPReport?, hops: [VisualTracerouteHop]) -> [VisualRouteLink] {
        let hopLinks = links(for: hops)
        guard let origin, let first = hops.first(where: { $0.geo != nil }) else {
            return hopLinks
        }
        let start = VisualRouteLink(
            ttl: first.id,
            fromLatitude: origin.latitude,
            fromLongitude: origin.longitude,
            toLatitude: first.geo?.latitude ?? 0,
            toLongitude: first.geo?.longitude ?? 0,
            milliseconds: first.hop.averageMilliseconds
        )
        return [start] + hopLinks
    }
}

enum VisualTracerouteFilter {
    static func isPublic(_ address: String) -> Bool {
        guard let ip = IPv4Address(address) else { return false }
        let parts = "\(ip)".split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let first = parts[0]
        let second = parts[1]
        if first == 10 || first == 127 || first == 0 { return false }
        if first == 169 && second == 254 { return false }
        if first == 172 && (16...31).contains(second) { return false }
        if first == 192 && second == 168 { return false }
        if first == 100 && (64...127).contains(second) { return false }
        if first >= 224 { return false }
        return true
    }
}
