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
        case .apName: return "AP Name"
        case .amendments: return "Amendments"
        case .annotations: return "Annotations"
        case .bssid: return "BSSID"
        case .band: return "Band"
        case .basicRates: return "Basic Rates"
        case .beaconAirtime: return "Beacon Airtime"
        case .beaconInterval: return "Beacon Interval"
        case .beaconMode: return "Beacon Mode"
        case .beaconRate: return "Beacon Rate"
        case .centerFrequency: return "Center Frequency"
        case .channel: return "Channel"
        case .channelUtilization: return "Channel Utilization"
        case .channelWidth: return "Width"
        case .clients: return "Clients"
        case .congestion: return "Congestion"
        case .count: return "Count"
        case .countryCode: return "Country Code"
        case .fastTransition: return "Fast Transition"
        case .firstSeen: return "First Seen"
        case .generation: return "Generation"
        case .ieCount: return "IE Count"
        case .ieTotalLength: return "IE Total Length"
        case .lastSeen: return "Last Seen"
        case .maxBasicRate: return "Max Basic Rate"
        case .maxRate: return "Max Rate"
        case .minBasicRate: return "Min Basic Rate"
        case .minRate: return "Min Rate"
        case .mode: return "Mode"
        case .networkName: return "Network Name"
        case .noise: return "Noise"
        case .protectionMode: return "Protection Mode"
        case .quality: return "Quality"
        case .snr: return "SNR"
        case .security: return "Security"
        case .seen: return "Seen"
        case .signal: return "Signal"
        case .stations: return "Stations"
        case .streams: return "Streams"
        case .type: return "Type"
        case .uptime: return "Uptime"
        case .vendor: return "Vendor"
        case .wideChannel: return "Wide Channel"
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
        .ieTotalLength, .type, .beaconMode,
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
