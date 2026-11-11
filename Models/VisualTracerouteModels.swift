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
