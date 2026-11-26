import Foundation

/// One BSSID remembered by the environment baseline.
struct NetworkBaselineEntry: Codable, Equatable, Identifiable {
    let bssid: String
    let ssid: String
    let vendor: String
    let channel: Int
    let signal: Int
    let firstSeen: Date

    var id: String { bssid }
}

struct NetworkBaselineState: Codable, Equatable {
    /// Nil until the first scan has been absorbed; that first scan seeds the
    /// baseline silently instead of announcing every network as new.
    var seededAt: Date?
    var baseline: [String: NetworkBaselineEntry] = [:]
    /// BSSIDs discovered since the baseline was accepted, newest last.
    var pending: [String: NetworkBaselineEntry] = [:]

    static let empty = NetworkBaselineState()
}

/// Persists the baseline so "new since last time" survives a relaunch.
struct NetworkBaselineStore {
    let url: URL

    init(url: URL = NetworkBaselineStore.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("network-baseline.json")
    }

    func load() -> NetworkBaselineState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NetworkBaselineState.self, from: data)) ?? .empty
    }

    func save(_ state: NetworkBaselineState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

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
