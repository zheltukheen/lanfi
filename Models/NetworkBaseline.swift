import Foundation
import LanFiCore

// Baseline values and their JSON store live in LanFiCore so the app, the CLI
// and tests agree on one format. The evaluator stays here because it needs the
// Wi-Fi model, which has not moved yet.
typealias NetworkBaselineEntry = LanFiCore.NetworkBaselineEntry
typealias NetworkBaselineState = LanFiCore.NetworkBaselineState
typealias NetworkBaselineStore = LanFiCore.NetworkBaselineStore

enum NetworkBaselineEvaluator {
    /// BSSIDs in this scan that are neither known nor already pending. Empty
    /// BSSIDs are skipped: without an identity there is nothing to compare.
    static func unseen(
        networks: [NetworkModel], state: NetworkBaselineState, now: Date = Date()
    ) -> [NetworkBaselineEntry] {
        var seen = Set<String>()
        return networks.compactMap { network -> NetworkBaselineEntry? in
            let bssid = network.bssid.uppercased()
            guard !bssid.isEmpty, !seen.contains(bssid) else { return nil }
            seen.insert(bssid)
            guard state.baseline[bssid] == nil, state.pending[bssid] == nil else { return nil }
            return NetworkBaselineEntry(
                bssid: bssid,
                ssid: network.ssid.isEmpty ? String(localized: "Hidden network") : network.ssid,
                vendor: network.vendor,
                channel: network.channel,
                signal: network.signal,
                firstSeen: now)
        }
        .sorted { $0.ssid == $1.ssid ? $0.bssid < $1.bssid : $0.ssid < $1.ssid }
    }
}
