import Foundation

// MARK: - Scan modes

/// How LanFi collects Wi-Fi networks.
///
/// - `active`: CoreWLAN's built-in `scanForNetworks`. Fast, but macOS only
///   probes the preferred scanning channels in 6 GHz, so standard-power and
///   non-PSC access points can be missing.
/// - `passive`: monitor-mode capture while listening on every supported
///   channel. Finds beacon-only, hidden and non-PSC 6 GHz networks.
/// - `directed`: passive listening on the channels the user picked.
enum ScanMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case active
    case passive
    case directed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return String(localized: "Active")
        case .passive: return String(localized: "Passive")
        case .directed: return String(localized: "Directed")
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "arrow.triangle.2.circlepath"
        case .passive: return "ear"
        case .directed: return "scope"
        }
    }

    var summary: String {
        switch self {
        case .active:
            return String(
                localized:
                    "macOS scans the channels it supports. Fast, but standard-power 6 GHz and beacon-only networks can be missed."
            )
        case .passive:
            return String(
                localized:
                    "Listen on every supported channel in monitor mode. Slower, and finds beacon-only and non-PSC 6 GHz access points."
            )
        case .directed:
            return String(
                localized:
                    "Passive listening on the channels you choose. Best for checking one 6 GHz channel without a full sweep."
            )
        }
    }
}

// MARK: - Hardware

/// What the machine can do, gathered once per sheet opening.
///
/// The value type stays free of CoreWLAN so capability rules are testable:
/// `ScanHardwareProbe` fills it in from `sysctl` and CoreWLAN at runtime.
struct ScanHardwareProfile: Equatable {
    let machineIdentifier: String
    let cpuBrand: String
    let interfaceNames: [String]

    static let unknown = ScanHardwareProfile(
        machineIdentifier: "", cpuBrand: "", interfaceNames: [])

    var hasWiFiInterface: Bool { !interfaceNames.isEmpty }

    /// Apple's N1 Wi-Fi chip (M5 Pro/Max, M5 Air and A18 Pro Macs) switches
    /// channels unreliably for third-party apps; WiFi Explorer and Airtool both
    /// document the limitation. Channel hopping would silently miss channels,
    /// so LanFi holds one channel per passive run instead.
    var hasAppleN1: Bool {
        let brand = cpuBrand.uppercased()
        return brand.contains("M5") || brand.contains("A18")
    }

    var displayName: String {
        guard !machineIdentifier.isEmpty else { return "" }
        return cpuBrand.isEmpty ? machineIdentifier : "\(machineIdentifier) · \(cpuBrand)"
    }
}

enum ScanModeSupport: Equatable {
    case available
    case limited(String)
    case unavailable(String)

    var isUsable: Bool {
        if case .unavailable = self { return false }
        return true
    }

    var isLimited: Bool {
        if case .limited = self { return true }
        return false
    }

    var explanation: String? {
        switch self {
        case .available: return nil
        case .limited(let text), .unavailable(let text): return text
        }
    }

    var badge: String? {
        switch self {
        case .available: return nil
        case .limited: return String(localized: "Limited")
        case .unavailable: return String(localized: "Unavailable")
        }
    }
}

struct ScanModeCapabilities: Equatable {
    let profile: ScanHardwareProfile
    let active: ScanModeSupport
    let passive: ScanModeSupport
    let directed: ScanModeSupport

    func support(for mode: ScanMode) -> ScanModeSupport {
        switch mode {
        case .active: return active
        case .passive: return passive
        case .directed: return directed
        }
    }

    static func evaluate(profile: ScanHardwareProfile) -> ScanModeCapabilities {
        guard profile.hasWiFiInterface else {
            let reason = String(
                localized:
                    "No Wi-Fi interface was found. Turn Wi-Fi on, then reopen this sheet."
            )
            return ScanModeCapabilities(
                profile: profile, active: .unavailable(reason),
                passive: .unavailable(reason), directed: .unavailable(reason))
        }

        if profile.hasAppleN1 {
            return ScanModeCapabilities(
                profile: profile,
                active: .available,
                passive: .limited(
                    String(
                        localized:
                            "This Mac uses Apple's N1 Wi-Fi chip, which cannot switch channels reliably for third-party apps. A full passive sweep would skip channels, so LanFi listens on a single channel per run. Use Directed mode to check a specific 6 GHz channel."
                    )),
                directed: .available
            )
        }

        return ScanModeCapabilities(
            profile: profile, active: .available, passive: .available, directed: .available)
    }
}

// MARK: - Channel plan

/// One channel LanFi will listen on, with the metadata the plan UI shows.
struct ScanChannelPlanItem: Identifiable, Hashable {
    let band: WiFiBand
    let channel: Int
    let dwellMilliseconds: Int
    let isPrimaryScanningChannel: Bool
    let isDFS: Bool
    /// The channel appeared in a Reduced Neighbor Report, so it is known to be
    /// in use and is listened to before a blind sweep reaches it.
    let isNeighborReported: Bool
    /// "PSC · LPI/SP" for 6 GHz, "DFS" for radar channels, otherwise nil.
    let regulatoryLabel: String?

    var id: String { "\(band.rawValue)-\(channel)" }
    var channelLabel: String { "\(band.label) · \(channel)" }
}

struct ScanChannelPlan: Equatable {
    let mode: ScanMode
    let items: [ScanChannelPlanItem]
    let warnings: [String]

    var isEmpty: Bool { items.isEmpty }

    var totalDuration: TimeInterval {
        Double(items.reduce(0) { $0 + $1.dwellMilliseconds }) / 1000
    }

    func count(in band: WiFiBand) -> Int {
        items.reduce(0) { $0 + ($1.band == band ? 1 : 0) }
    }

    var sixGHzNonPreferredCount: Int {
        items.reduce(0) { $0 + ($1.band == .band6 && !$1.isPrimaryScanningChannel ? 1 : 0) }
    }

    var bands: [WiFiBand] {
        WiFiBand.allCases.filter { band in items.contains { $0.band == band } }
    }

    var summary: String {
        guard !items.isEmpty else { return String(localized: "No channels planned") }
        let counts = bands.map { "\($0.label) \(count(in: $0))" }.joined(separator: " · ")
        return counts
    }
}

enum ScanChannelPlanner {
    static let defaultDwellMilliseconds = 150
    static let minimumDwellMilliseconds = 50
    static let maximumDwellMilliseconds = 1000

    /// 802.11 beacons are sent every 102.4 ms by default. A shorter dwell can
    /// land between two beacons and miss the access point entirely.
    static let beaconIntervalHintMilliseconds = 110

    static func plan(
        mode: ScanMode,
        supported: [SupportedChannel],
        dwellMilliseconds: Int = defaultDwellMilliseconds,
        directedChannels: Set<String> = [],
        neighborChannels: [Int] = [],
        profile: ScanHardwareProfile = .unknown
    ) -> ScanChannelPlan {
        let dwell = min(
            max(dwellMilliseconds, minimumDwellMilliseconds), maximumDwellMilliseconds)
        let neighbors = Set(neighborChannels)

        var seen = Set<String>()
        let unique = supported.filter { channel in
            channel.channel > 0 && seen.insert(channel.id).inserted
        }

        var selected = unique
        if mode == .directed {
            selected = unique.filter { directedChannels.contains($0.id) }
        }

        let ordered = order(selected, neighbors: neighbors)
        var items = ordered.map { channel in
            let isPSC = ScanChannelRegulation.isPrimaryScanningChannel(
                band: channel.band, channel: channel.channel)
            return ScanChannelPlanItem(
                band: channel.band,
                channel: channel.channel,
                dwellMilliseconds: mode == .active ? 0 : dwell,
                isPrimaryScanningChannel: isPSC,
                isDFS: ScanChannelRegulation.isDFS(
                    band: channel.band, channel: channel.channel),
                isNeighborReported: neighbors.contains(channel.channel),
                regulatoryLabel: ScanChannelRegulation.label(
                    band: channel.band, channel: channel.channel, isPrimaryScanningChannel: isPSC)
            )
        }

        var warnings: [String] = []
        if profile.interfaceNames.isEmpty {
            warnings.append(
                String(localized: "No Wi-Fi interface was found."))
        }
        if mode == .directed && directedChannels.isEmpty {
            warnings.append(String(localized: "Select at least one channel to listen on."))
        }
        if mode == .passive && profile.hasAppleN1 && items.count > 1 {
            items = Array(items.prefix(1))
            warnings.append(
                String(
                    localized:
                        "Apple N1 hardware cannot hop channels reliably, so this run listens on one channel. Use Directed mode to pick a different channel."
                ))
        }
        if mode != .active && dwell < beaconIntervalHintMilliseconds {
            warnings.append(
                String(
                    localized:
                        "A dwell under 110 ms can miss a beacon: access points send one every 102.4 ms by default."
                ))
        }
        if mode == .passive && items.count > 1,
            let psc = items.first(where: { $0.band == .band6 && $0.isPrimaryScanningChannel })
        {
            warnings.append(
                String(
                    localized:
                        "6 GHz listening starts with PSC channel \(psc.channel); non-PSC channels active scans skip are included."
                ))
        }
        if mode != .active, items.contains(where: { $0.band == .band6 }) {
            warnings.append(
                String(
                    localized:
                        "6 GHz power mode is labelled per access point: LPI indoors, SP only where an AFC allows it."
                ))
        }

        return ScanChannelPlan(mode: mode, items: items, warnings: warnings)
    }

    /// 6 GHz is ordered RNR-reported first, then preferred scanning channels,
    /// then the rest, so the informative channels are captured early. Other
    /// bands stay in ascending channel order.
    private static func order(
        _ channels: [SupportedChannel], neighbors: Set<Int>
    ) -> [SupportedChannel] {
        channels.sorted { lhs, rhs in
            if lhs.band != rhs.band { return lhs.band.sortOrder < rhs.band.sortOrder }
            if lhs.band == .band6 {
                let left = rank(lhs.channel, neighbors: neighbors)
                let right = rank(rhs.channel, neighbors: neighbors)
                if left != right { return left < right }
            }
            return lhs.channel < rhs.channel
        }
    }

    private static func rank(_ channel: Int, neighbors: Set<Int>) -> Int {
        if neighbors.contains(channel) { return 0 }
        return NetworkModel.preferredScanningChannels6GHz.contains(channel) ? 1 : 2
    }
}

enum ScanChannelRegulation {
    static func isPrimaryScanningChannel(band: WiFiBand, channel: Int) -> Bool {
        band == .band6 && NetworkModel.preferredScanningChannels6GHz.contains(channel)
    }

    /// 5 GHz channels shared with radar in most regulatory domains.
    static func isDFS(band: WiFiBand, channel: Int) -> Bool {
        band == .band5 && (52...144).contains(channel)
    }

    static func label(band: WiFiBand, channel: Int, isPrimaryScanningChannel: Bool) -> String? {
        switch band {
        case .band6:
            return isPrimaryScanningChannel ? "PSC · LPI/SP" : "LPI/SP"
        case .band5:
            return isDFS(band: band, channel: channel) ? "DFS" : nil
        case .band24, .unknown:
            return nil
        }
    }
}

// MARK: - Progress

struct PassiveScanProgress: Equatable {
    enum Phase: String, Equatable {
        case preparing
        case capturing
        case reading
        case finished
    }

    var phase: Phase
    var completed: Int
    var total: Int
    var channel: ScanChannelPlanItem?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var label: String {
        switch phase {
        case .preparing:
            return String(localized: "Starting monitor capture…")
        case .capturing:
            guard let channel else { return String(localized: "Listening…") }
            return String(
                localized:
                    "\(completed + 1) of \(total) · \(channel.channelLabel)")
        case .reading:
            return String(localized: "Reading captured beacons…")
        case .finished:
            return String(localized: "Finished")
        }
    }
}
