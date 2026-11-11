import Foundation

struct GeoIPReport: Equatable, Sendable {
    let query: String
    let ip: String
    let type: String
    let continent: String
    let country: String
    let countryCode: String
    let flag: String
    let region: String
    let city: String
    let latitude: Double
    let longitude: Double
    let asn: Int?
    let organization: String
    let isp: String
    let timezone: String
    let utcOffset: String

    var locationLine: String {
        [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var coordinateText: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    var flagEmoji: String {
        let code = countryCode.uppercased()
        guard code.count == 2 else { return flag.isEmpty ? "🌐" : flag }
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }
        return scalars.isEmpty ? "🌐" : String(String.UnicodeScalarView(scalars))
    }
}

enum GeoIPError: Error, Equatable, LocalizedError {
    case invalidTarget
    case httpStatus(Int)
    case invalidResponse
    case lookupFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTarget:
            return "Enter an IP address or hostname."
        case .httpStatus(let status):
            return "GeoIP returned HTTP \(status)."
        case .invalidResponse:
            return "GeoIP returned an unexpected response."
        case .lookupFailed(let message):
            return message
        }
    }
}
