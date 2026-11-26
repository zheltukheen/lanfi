import Foundation

/// G7: what one BSSID cost the channel in a capture, measured from the
/// Duration/ID field of the frames it transmitted. Neither Wireshark nor a scan
/// gives this for a passive capture, and it answers "is the load mine or the
/// neighbour's?".
struct ChannelAirtimeEntry: Identifiable, Equatable {
    let bssid: String
    let ssid: String
    var frames: Int = 0
    var airtimeMicroseconds: Int = 0
    var dataFrames: Int = 0
    /// Directed data frames transmitted at 1, 2, 5.5 or 11 Mbit/s.
    var legacyFrames: Int = 0
    /// Share of all transmitted airtime in this capture, when any frame carried
    /// a duration.
    var share: Double? = nil

    var id: String { bssid }
    var airtimeMilliseconds: Int { airtimeMicroseconds / 1000 }
    var isLegacy: Bool { legacyFrames > 0 }
}

/// G7: legacy-rate detection. A BSSID that advertises only 802.11b basic rates
/// drags every client on its channel down to DSSS rates, which is the single
/// most common cause of "the Wi-Fi is slow for no reason".
enum LegacyWiFiDetector {
    /// 802.11b rates in Mbit/s.
    static let legacyBasicRates: Set<Double> = [1, 2, 5.5, 11]

    static func isLegacyRate(_ mbps: Double) -> Bool {
        mbps > 0 && mbps <= 11.1
    }

    /// True when every advertised basic rate is an 802.11b rate. A mixed-mode
    /// beacon (6/12/24 plus 1/2) is normal and is not flagged.
    static func hasOnlyLegacyBasicRates(_ rates: [Double]?) -> Bool {
        guard let rates, !rates.isEmpty else { return false }
        let unique = Set(rates.filter { $0 > 0 })
        guard !unique.isEmpty else { return false }
        return unique.allSatisfy { isLegacyRate($0) }
    }

    static func flag(_ network: NetworkModel) -> Bool {
        hasOnlyLegacyBasicRates(network.basicRates)
    }

    /// One sentence for the report and the analytics card, or nil when clean.
    static func summary(for network: NetworkModel) -> String? {
        guard flag(network) else { return nil }
        let rates = (network.basicRates ?? []).map { String(format: "%.1f", $0) }.joined(separator: "/")
        return String(
            format: String(
                localized:
                    "%@ advertises only 802.11b basic rates (%@ Mbit/s). One such device keeps the whole channel at legacy speeds."
            ), network.displaySSID, rates)
    }
}
