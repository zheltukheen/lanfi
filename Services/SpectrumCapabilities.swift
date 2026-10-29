import CoreWLAN
import Foundation

enum SpectrumCapabilities {
    static func current() -> [SupportedChannel] {
        let client = CWWiFiClient.shared()
        let preferred = UserDefaults.standard.string(forKey: "LanFi.wifiInterface")
        let interface = preferred.flatMap { client.interface(withName: $0) } ?? client.interface()
        let channels = interface?.supportedWLANChannels() ?? []
        let supported = channels.compactMap { channel -> SupportedChannel? in
            guard let band = mapBand(channel.channelBand), channel.channelNumber > 0 else { return nil }
            return SupportedChannel(band: band, channel: channel.channelNumber)
        }
        if !supported.isEmpty {
            return Array(Set(supported)).sorted {
                $0.band.sortOrder == $1.band.sortOrder
                    ? $0.channel < $1.channel
                    : $0.band.sortOrder < $1.band.sortOrder
            }
        }
        return fallback()
    }

    static func fallback() -> [SupportedChannel] {
        var result: [SupportedChannel] = []
        result += (1...14).map { SupportedChannel(band: .band24, channel: $0) }
        result += stride(from: 36, through: 165, by: 4).map { SupportedChannel(band: .band5, channel: $0) }
        result += stride(from: 1, through: 233, by: 4).map { SupportedChannel(band: .band6, channel: $0) }
        return result
    }

    private static func mapBand(_ band: CWChannelBand?) -> WiFiBand? {
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return nil
        }
    }
}
