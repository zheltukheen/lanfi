import AppKit
import Foundation

// MARK: - Column Definitions

enum ColumnId: String, CaseIterable, Codable {
    case apName
    case amendments
    case annotations
    case bssid
    case band
    case basicRates
    case beaconAirtime
    case beaconInterval
    case beaconMode
    case beaconRate
    case centerFrequency
    case channel
    case channelUtilization
    case channelWidth
    case clients
    case congestion
    case count
    case countryCode
    case fastTransition
    case firstSeen
    case generation
    case ieCount
    case ieTotalLength
    case lastSeen
    case maxBasicRate
    case maxRate
    case minBasicRate
    case minRate
    case mode
    case networkName
    case noise
    case protectionMode
    case puncturing
    case quality
    case snr
    case security
    case seen
    case signal
    case stations
    case streams
    case type
    case uptime
    case vendor
    case wideChannel

    var defaultTitle: String {
        switch self {
        case .apName: return String(localized: "AP Name")
        case .amendments: return String(localized: "Amendments")
        case .annotations: return String(localized: "Annotations")
        case .bssid: return String(localized: "BSSID")
        case .band: return String(localized: "Band")
        case .basicRates: return String(localized: "Basic Rates")
        case .beaconAirtime: return String(localized: "Beacon Airtime")
        case .beaconInterval: return String(localized: "Beacon Interval")
        case .beaconMode: return String(localized: "Beacon Mode")
        case .beaconRate: return String(localized: "Beacon Rate")
        case .centerFrequency: return String(localized: "Center Frequency")
        case .channel: return String(localized: "Channel")
        case .channelUtilization: return String(localized: "Channel Utilization")
        case .channelWidth: return String(localized: "Width")
        case .clients: return String(localized: "Clients")
        case .congestion: return String(localized: "Congestion")
        case .count: return String(localized: "Count")
        case .countryCode: return String(localized: "Country Code")
        case .fastTransition: return String(localized: "Fast Transition")
        case .firstSeen: return String(localized: "First Seen")
        case .generation: return String(localized: "Generation")
        case .ieCount: return String(localized: "IE Count")
        case .ieTotalLength: return String(localized: "IE Total Length")
        case .lastSeen: return String(localized: "Last Seen")
        case .maxBasicRate: return String(localized: "Max Basic Rate")
        case .maxRate: return String(localized: "Max Rate")
        case .minBasicRate: return String(localized: "Min Basic Rate")
        case .minRate: return String(localized: "Min Rate")
        case .mode: return String(localized: "Mode")
        case .networkName: return String(localized: "Network Name")
        case .noise: return String(localized: "Noise")
        case .protectionMode: return String(localized: "Protection Mode")
        case .puncturing: return String(localized: "Puncturing")
        case .quality: return String(localized: "Quality")
        case .snr: return String(localized: "SNR")
        case .security: return String(localized: "Security")
        case .seen: return String(localized: "Seen")
        case .signal: return String(localized: "Signal")
        case .stations: return String(localized: "Stations")
        case .streams: return String(localized: "Streams")
        case .type: return String(localized: "Type")
        case .uptime: return String(localized: "Uptime")
        case .vendor: return String(localized: "Vendor")
        case .wideChannel: return String(localized: "Wide Channel")
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .signal, .quality:
            return 80
        case .channel, .congestion:
            return 70
        case .count, .seen, .clients, .stations, .streams, .noise, .snr, .wideChannel:
            return 70
        case .band:
            return 75
        case .generation, .mode:
            return 85
        case .type:
            return 90
        case .security:
            return 100
        case .channelWidth, .maxRate, .minRate, .maxBasicRate, .minBasicRate, .beaconInterval, .beaconRate:
            return 75
        case .centerFrequency, .countryCode, .fastTransition, .beaconMode, .beaconAirtime, .channelUtilization:
            return 110
        case .firstSeen, .lastSeen, .uptime:
            return 130
        case .networkName:
            return 150
        case .bssid:
            return 140
        case .vendor:
            return 130
        case .basicRates, .annotations, .apName:
            return 150
        case .amendments, .ieCount, .ieTotalLength:
            return 120
        case .protectionMode:
            return 160
        case .puncturing:
            return 90
        }
    }

    var defaultAlignment: ColumnAlignment {
        switch self {
        case .signal, .channel, .channelWidth, .count, .seen, .clients, .stations, .streams, .noise, .snr,
            .centerFrequency, .channelUtilization, .beaconInterval, .beaconRate, .beaconAirtime, .maxRate, .minRate,
            .maxBasicRate, .minBasicRate, .ieCount, .ieTotalLength, .uptime, .quality, .congestion:
            return .right
        case .wideChannel, .fastTransition:
            return .center
        default:
            return .left
        }
    }

    var defaultVisibility: Bool {
        switch self {
        case .networkName, .signal, .quality, .band, .channel, .channelWidth,
            .security, .vendor, .bssid, .maxRate, .mode:
            return true
        default:
            return false
        }
    }

    /// Sensible out-of-the-box column order: identity, signal, interpretation,
    /// radio details, then the long tail of 802.11 fields.
    static let displayOrder: [ColumnId] = [
        .networkName, .signal, .quality, .band, .channel, .channelWidth,
        .security, .vendor, .bssid, .generation, .maxRate, .mode, .snr, .noise,
        .seen, .lastSeen, .firstSeen, .uptime, .congestion, .channelUtilization,
        .clients, .stations, .streams, .countryCode, .fastTransition,
        .protectionMode, .beaconInterval, .beaconRate, .beaconAirtime, .wideChannel,
        .centerFrequency, .basicRates, .minRate, .minBasicRate,
        .maxBasicRate, .amendments, .annotations, .apName, .count, .ieCount,
        .ieTotalLength, .type, .beaconMode, .puncturing,
    ]
}

enum ColumnAlignment: Int, Codable {
    case left = 0
    case center = 1
    case right = 2

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

// MARK: - Models

struct ColumnDefinition: Identifiable, Codable {
    var id: String
    var title: String
    var width: CGFloat
    var isVisible: Bool
    var order: Int
    var alignment: ColumnAlignment = .left
    var isPinned: Bool = false
    var customTitle: String? = nil

    var displayTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        return title
    }

    static let defaults: [ColumnDefinition] = {
        ColumnId.displayOrder.enumerated().map { index, column in
            ColumnDefinition(
                id: column.rawValue,
                title: column.defaultTitle,
                width: column.defaultWidth,
                isVisible: column.defaultVisibility,
                order: index,
                alignment: column.defaultAlignment
            )
        }
    }()
}
