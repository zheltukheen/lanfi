import Foundation

/// One BSSID remembered by the environment baseline.
public struct NetworkBaselineEntry: Codable, Equatable, Identifiable, Sendable {
    public let bssid: String
    public let ssid: String
    public let vendor: String
    public let channel: Int
    public let signal: Int
    public let firstSeen: Date

    public init(
        bssid: String, ssid: String, vendor: String, channel: Int, signal: Int,
        firstSeen: Date
    ) {
        self.bssid = bssid
        self.ssid = ssid
        self.vendor = vendor
        self.channel = channel
        self.signal = signal
        self.firstSeen = firstSeen
    }

    public var id: String { bssid }
}

public struct NetworkBaselineState: Codable, Equatable, Sendable {
    /// Nil until the first scan has been absorbed; that first scan seeds the
    /// baseline silently instead of announcing every network as new.
    public var seededAt: Date?
    public var baseline: [String: NetworkBaselineEntry]
    /// BSSIDs discovered since the baseline was accepted.
    public var pending: [String: NetworkBaselineEntry]

    public init(
        seededAt: Date? = nil, baseline: [String: NetworkBaselineEntry] = [:],
        pending: [String: NetworkBaselineEntry] = [:]
    ) {
        self.seededAt = seededAt
        self.baseline = baseline
        self.pending = pending
    }

    public static let empty = NetworkBaselineState()
}

/// Persists the baseline so "new since last time" survives a relaunch.
public struct NetworkBaselineStore: Sendable {
    public let url: URL

    public init(url: URL = NetworkBaselineStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("network-baseline.json")
    }

    public func load() -> NetworkBaselineState {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NetworkBaselineState.self, from: data)) ?? .empty
    }

    public func save(_ state: NetworkBaselineState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
