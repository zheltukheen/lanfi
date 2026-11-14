import Foundation

struct CaptureProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var interfaceName: String
    var duration: Int
    var monitorMode: Bool
    var filter: String
    var channel: Int? = nil
    /// Channels of interest, e.g. 1,6,11 or every channel of a band. macOS
    /// hops across channels while in monitor mode, so the interface is only
    /// pinned when exactly one channel is listed.
    var channels: [Int]? = nil

    /// The single channel the capture would pin, if the profile describes one.
    var pinnedChannel: Int? {
        if let channels { return channels.count == 1 ? channels.first : nil }
        return channel
    }

    var channelListLabel: String {
        guard let channels, !channels.isEmpty else { return "Auto" }
        return channels.map(String.init).joined(separator: ",")
    }

    static func new(
        name: String, interfaceName: String, duration: Int, monitorMode: Bool, filter: String,
        channel: Int? = nil, channels: [Int]? = nil
    ) -> CaptureProfile {
        CaptureProfile(
            id: UUID(), name: name, interfaceName: interfaceName,
            duration: duration, monitorMode: monitorMode, filter: filter, channel: channel,
            channels: channels
        )
    }

    /// Parses "1, 6, 11" into unique in-range channel numbers.
    static func parseChannels(_ text: String) -> [Int] {
        var seen = Set<Int>()
        return
            text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
            .compactMap { Int($0) }
            .filter { (1...233).contains($0) && seen.insert($0).inserted }
    }

    /// Channels of the given bands among the channels the radio supports.
    static func channels(for bands: Set<WiFiBand>, available: [SupportedChannel]) -> [Int] {
        var seen = Set<Int>()
        return
            available
            .filter { bands.contains($0.band) }
            .map(\.channel)
            .sorted()
            .filter { seen.insert($0).inserted }
    }
}

final class CaptureProfileStore {
    private let defaults: UserDefaults
    private let key = "LanFi.captureProfiles"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [CaptureProfile] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CaptureProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [CaptureProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: key)
    }
}
