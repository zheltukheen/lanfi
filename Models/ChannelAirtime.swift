import Foundation
import LanFiCore

// The airtime value lives in LanFiCore; the detector stays here because it
// reads the Wi-Fi model, which has not moved yet.
typealias ChannelAirtimeEntry = LanFiCore.ChannelAirtimeEntry

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
