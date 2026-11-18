import Foundation

/// Physical channel geometry for the all-band RF overview.
///
/// Everything is expressed in MHz so overlap is computed physically instead of
/// by channel-number arithmetic: channel numbers are not evenly spaced in
/// frequency and their meaning changes between bands.
enum RFBandGeometry {
    static let defaultBandwidthMHz = 20.0

    /// Nominal centre frequency of an 802.11 channel, or `nil` when the channel
    /// cannot belong to the band (guards against junk scan values).
    static func centerFrequencyMHz(channel: Int, band: WiFiBand) -> Double? {
        guard channel > 0 else { return nil }
        switch band {
        case .band24:
            if channel == 14 { return 2484 }
            guard (1...13).contains(channel) else { return nil }
            return 2407 + 5 * Double(channel - 1)
        case .band5:
            guard (30...190).contains(channel) else { return nil }
            return 5000 + 5 * Double(channel)
        case .band6:
            guard (1...233).contains(channel) else { return nil }
            return 5950 + 5 * Double(channel)
        case .unknown:
            return 2407 + 5 * Double(channel - 1)
        }
    }

    /// Plot domain per band, wide enough for the edges of the widest channels.
    static func domainMHz(for band: WiFiBand) -> ClosedRange<Double> {
        switch band {
        case .band24: return 2392...2497
        case .band5: return 5140...5905
        case .band6: return 5935...7145
        case .unknown: return 2392...2497
        }
    }

    /// Channels that get a grid line and a label on the band axis.
    static func tickChannels(for band: WiFiBand) -> [Int] {
        switch band {
        case .band24: return [1, 3, 5, 7, 9, 11, 13]
        case .band5: return [36, 52, 64, 100, 116, 132, 149, 165]
        case .band6: return [1, 37, 69, 101, 133, 165, 197, 229]
        case .unknown: return [1, 6, 11]
        }
    }
}

/// Pure layout for one band of the RF overview: every AP as a frequency span,
/// the regions where two or more spans collide, and the recommended channel.
struct RFOverviewLayout: Equatable {
    struct Span: Identifiable, Equatable {
        let id: String
        let ssid: String
        let channel: Int
        let widthMHz: Int
        let startMHz: Double
        let endMHz: Double
        let signal: Int
        let isConnected: Bool
        /// Number of *other* networks whose span intersects this one.
        let overlapCount: Int

        var centerMHz: Double { (startMHz + endMHz) / 2 }
    }

    struct HotRegion: Equatable {
        let startMHz: Double
        let endMHz: Double
        let depth: Int
    }

    struct Marker: Equatable {
        let channel: Int
        let widthMHz: Int
        let startMHz: Double
        let endMHz: Double
        let score: Int
        let isDFS: Bool
    }

    let band: WiFiBand
    let domainMHz: ClosedRange<Double>
    let spans: [Span]
    let hotRegions: [HotRegion]
    let marker: Marker?
    let networkCount: Int
    let strongestSignal: Int?
    /// Deepest simultaneous overlap in the band; 1 means "no overlap".
    let maxDepth: Int

    var isEmpty: Bool { spans.isEmpty }

    /// Channel shared by the most other networks, if any channel is shared.
    var busiestChannel: Int? {
        guard
            let worst = spans.max(by: { lhs, rhs in
                lhs.overlapCount == rhs.overlapCount
                    ? lhs.id > rhs.id
                    : lhs.overlapCount < rhs.overlapCount
            }),
            worst.overlapCount > 0
        else { return nil }
        return worst.channel
    }

    static func build(
        band: WiFiBand,
        networks: [NetworkModel],
        connectedBSSID: String?,
        recommendation: ChannelRecommendation?
    ) -> RFOverviewLayout {
        let domain = RFBandGeometry.domainMHz(for: band)
        var spans: [Span] = []

        for network in networks where network.band == band {
            guard
                let center = RFBandGeometry.centerFrequencyMHz(
                    channel: network.channel, band: band)
            else { continue }
            let width =
                network.channelWidthMHz > 0
                ? Double(network.channelWidthMHz)
                : RFBandGeometry.defaultBandwidthMHz
            let start = max(center - width / 2, domain.lowerBound)
            let end = min(center + width / 2, domain.upperBound)
            guard end > start else { continue }
            spans.append(
                Span(
                    id: network.id,
                    ssid: network.displaySSID,
                    channel: network.channel,
                    widthMHz: network.channelWidthMHz > 0 ? network.channelWidthMHz : Int(width),
                    startMHz: start,
                    endMHz: end,
                    signal: network.signal,
                    isConnected: connectedBSSID != nil && network.bssid == connectedBSSID,
                    overlapCount: 0
                )
            )
        }

        spans.sort { lhs, rhs in
            if lhs.startMHz != rhs.startMHz { return lhs.startMHz < rhs.startMHz }
            if lhs.endMHz != rhs.endMHz { return lhs.endMHz > rhs.endMHz }
            return lhs.id < rhs.id
        }

        let overlaps = spans.map { span in
            spans.filter { other in
                other.id != span.id && intersects(span, other)
            }.count
        }
        for index in spans.indices {
            spans[index] = Span(
                id: spans[index].id,
                ssid: spans[index].ssid,
                channel: spans[index].channel,
                widthMHz: spans[index].widthMHz,
                startMHz: spans[index].startMHz,
                endMHz: spans[index].endMHz,
                signal: spans[index].signal,
                isConnected: spans[index].isConnected,
                overlapCount: overlaps[index]
            )
        }

        let hotRegions = buildHotRegions(spans)
        let recommendedMarker: Marker?
        if let recommendation {
            recommendedMarker = Self.marker(for: recommendation, band: band, domain: domain)
        } else {
            recommendedMarker = nil
        }

        return RFOverviewLayout(
            band: band,
            domainMHz: domain,
            spans: spans,
            hotRegions: hotRegions,
            marker: recommendedMarker,
            networkCount: spans.count,
            strongestSignal: spans.map(\.signal).max(),
            maxDepth: hotRegions.map(\.depth).max() ?? (spans.isEmpty ? 0 : 1)
        )
    }

    // MARK: - Internals

    private static let epsilonMHz = 0.01

    private static func intersects(_ lhs: Span, _ rhs: Span) -> Bool {
        lhs.startMHz < rhs.endMHz - epsilonMHz && rhs.startMHz < lhs.endMHz - epsilonMHz
    }

    /// Sweeps the span boundaries and keeps the segments covered by 2+ spans,
    /// merging neighbours with the same coverage so the view can shade them.
    private static func buildHotRegions(_ spans: [Span]) -> [HotRegion] {
        guard spans.count > 1 else { return [] }
        let boundaries = Set(spans.flatMap { [$0.startMHz, $0.endMHz] }).sorted()
        guard boundaries.count > 1 else { return [] }

        var regions: [HotRegion] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end - start > epsilonMHz else { continue }
            let middle = (start + end) / 2
            let depth = spans.filter { $0.startMHz <= middle && $0.endMHz >= middle }.count
            guard depth >= 2 else { continue }
            if let last = regions.last, abs(last.endMHz - start) < epsilonMHz,
                last.depth == depth
            {
                regions[regions.count - 1] = HotRegion(
                    startMHz: last.startMHz, endMHz: end, depth: depth)
            } else {
                regions.append(HotRegion(startMHz: start, endMHz: end, depth: depth))
            }
        }
        return regions
    }

    private static func marker(
        for recommendation: ChannelRecommendation,
        band: WiFiBand,
        domain: ClosedRange<Double>
    ) -> Marker? {
        guard
            let center = RFBandGeometry.centerFrequencyMHz(
                channel: recommendation.channel, band: band)
        else { return nil }
        let width =
            recommendation.widthMHz > 0
            ? Double(recommendation.widthMHz)
            : RFBandGeometry.defaultBandwidthMHz
        let start = max(center - width / 2, domain.lowerBound)
        let end = min(center + width / 2, domain.upperBound)
        guard end > start else { return nil }
        return Marker(
            channel: recommendation.channel,
            widthMHz: recommendation.widthMHz,
            startMHz: start,
            endMHz: end,
            score: recommendation.score,
            isDFS: recommendation.isDFS
        )
    }
}
