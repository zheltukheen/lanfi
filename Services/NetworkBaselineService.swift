import Combine
import Foundation

/// Keeps a baseline of the access points around this Mac and reports the ones
/// that appeared afterwards.
///
/// The first scan seeds the baseline without announcing anything: otherwise the
/// feature would fire for every neighbour on first launch. A BSSID is announced
/// once, stays in `pending` until the user accepts it, and never fires again
/// after a relaunch — the pending list is persisted next to the baseline.
@MainActor
final class NetworkBaselineService: ObservableObject {
    static let shared = NetworkBaselineService()

    @Published private(set) var pending: [NetworkBaselineEntry] = []
    @Published private(set) var knownCount = 0
    @Published private(set) var seededAt: Date?

    private var state: NetworkBaselineState
    private let store: NetworkBaselineStore
    /// Tests build the service without posting notifications.
    private let postsEvents: Bool

    init(store: NetworkBaselineStore = NetworkBaselineStore(), postsEvents: Bool = true) {
        self.store = store
        self.postsEvents = postsEvents
        let loaded = store.load()
        state = loaded
        publish(loaded)
    }

    var isSeeded: Bool { state.seededAt != nil }

    /// Folds one scan into the baseline. The first call seeds; later calls add
    /// unseen BSSIDs and post one security event per BSSID.
    func observe(_ networks: [NetworkModel], now: Date = Date()) {
        guard !networks.isEmpty else { return }
        if state.seededAt == nil {
            var seeded = state
            seeded.seededAt = now
            for network in networks {
                let bssid = network.bssid.uppercased()
                guard !bssid.isEmpty else { continue }
                seeded.baseline[bssid] = entry(for: network, at: now)
            }
            state = seeded
            persist()
            return
        }

        let fresh = NetworkBaselineEvaluator.unseen(networks: networks, state: state, now: now)
        guard !fresh.isEmpty else { return }
        var updated = state
        for entry in fresh {
            updated.pending[entry.bssid] = entry
        }
        // One event per scan: the alert policy allows one banner per kind per
        // cooldown, so posting one per BSSID would only hide the rest.
        if postsEvents {
            let names = fresh.prefix(3).map { "\($0.ssid) (\($0.bssid))" }.joined(separator: ", ")
            let extra = fresh.count > 3 ? " and \(fresh.count - 3) more" : ""
            SecurityEvent.post(
                .newAccessPoint,
                subject: fresh.count == 1 ? fresh[0].ssid : "\(fresh.count) new access points",
                detail: String(
                    localized:
                        "BSSIDs outside the baseline appeared: \(names)\(extra). If they are yours, accept them; if not, check whether they belong to a neighbour or an unauthorized AP."
                ),
                bssid: fresh.count == 1 ? fresh[0].bssid : "")
        }
        state = updated
        persist()
    }

    /// Moves every pending BSSID into the known baseline.
    func acceptPending(now: Date = Date()) {
        guard !state.pending.isEmpty else { return }
        var updated = state
        for (bssid, entry) in updated.pending {
            updated.baseline[bssid] = entry
        }
        updated.pending.removeAll()
        updated.seededAt = updated.seededAt ?? now
        state = updated
        persist()
    }

    /// Forgets everything. The next scan seeds a fresh baseline silently.
    func reset() {
        state = .empty
        persist()
    }

    private func entry(for network: NetworkModel, at date: Date) -> NetworkBaselineEntry {
        NetworkBaselineEntry(
            bssid: network.bssid.uppercased(),
            ssid: network.ssid.isEmpty ? String(localized: "Hidden network") : network.ssid,
            vendor: network.vendor,
            channel: network.channel,
            signal: network.signal,
            firstSeen: date)
    }

    private func persist() {
        publish(state)
        try? store.save(state)
    }

    private func publish(_ state: NetworkBaselineState) {
        pending = state.pending.values.sorted {
            $0.ssid == $1.ssid ? $0.bssid < $1.bssid : $0.ssid < $1.ssid
        }
        knownCount = state.baseline.count
        seededAt = state.seededAt
    }
}
