import Foundation

// MARK: - Scores and findings

enum QualityGrade: String {
    case excellent
    case good
    case fair
    case poor

    init(score: Int) {
        switch score {
        case 85...: self = .excellent
        case 65..<85: self = .good
        case 40..<65: self = .fair
        default: self = .poor
        }
    }

    var label: String { rawValue.capitalized }
}

enum IssueSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: IssueSeverity, rhs: IssueSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }
}

enum IssueCategory: Equatable {
    case security
    case performance
    case configuration
}

struct NetworkIssue: Identifiable, Equatable {
    let id: String
    let severity: IssueSeverity
    let category: IssueCategory
    let title: String
    let detail: String
}

struct SecurityFinding: Identifiable, Equatable {
    let id: String
    let networkId: String
    let ssid: String
    let bssid: String
    let severity: IssueSeverity
    let title: String
    let detail: String
}

struct NetworkMetrics: Identifiable, Equatable {
    var id: String { networkId }

    let networkId: String
    let qualityScore: Int
    let signalScore: Int
    let snrScore: Int?
    let congestionScore: Int
    let utilizationScore: Int?
    let securityScore: Int
    let coChannelCount: Int
    let overlappingCount: Int
    let interferenceLoad: Double
    let issues: [NetworkIssue]

    var grade: QualityGrade { QualityGrade(score: qualityScore) }

    var securityIssues: [NetworkIssue] {
        issues.filter { $0.category == .security }
    }
}

struct ChannelRecommendation: Identifiable, Equatable {
    var id: String { "\(band.rawValue)-\(channel)-\(widthMHz)" }

    let band: WiFiBand
    let channel: Int
    let widthMHz: Int
    let score: Int
    let overlappingCount: Int
    let coChannelCount: Int
    let isDFS: Bool
    let rationale: String
}

struct ChannelOccupancy: Identifiable, Equatable {
    var id: String { "\(band.rawValue)-\(channel)" }

    let band: WiFiBand
    let channel: Int
    let networkCount: Int
    let strongestRSSI: Int
    let averageRSSI: Int
}

struct AnalysisReport {
    static let empty = AnalysisReport(
        metricsByNetworkId: [:],
        recommendationsByBand: [:],
        securityFindings: [],
        occupancy: [],
        averageQuality: 0,
        analyzedNetworkCount: 0
    )

    let metricsByNetworkId: [String: NetworkMetrics]
    let recommendationsByBand: [WiFiBand: [ChannelRecommendation]]
    let securityFindings: [SecurityFinding]
    let occupancy: [ChannelOccupancy]
    let averageQuality: Int
    let analyzedNetworkCount: Int

    func metrics(for networkId: String) -> NetworkMetrics? {
        metricsByNetworkId[networkId]
    }

    func bestChannel(for band: WiFiBand) -> ChannelRecommendation? {
        recommendationsByBand[band]?.first
    }

    func recommendations(for band: WiFiBand) -> [ChannelRecommendation] {
        recommendationsByBand[band] ?? []
    }

    var criticalFindingCount: Int {
        securityFindings.filter { $0.severity == .critical }.count
    }
}

// MARK: - Analyzer

/// Pure, deterministic analysis of a Wi-Fi scan. No CoreWLAN or UI
/// dependencies, which keeps the scoring rules unit-testable.
enum NetworkAnalyzer {

    struct Candidate {
        let channel: Int
        let widthMHz: Int
    }

    private static let ghz24Channels = [1, 6, 11]
    private static let ghz5Channels = [
        36, 40, 44, 48, 52, 56, 60, 64,
        100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
        149, 153, 157, 161, 165,
    ]
    private static let ghz6PSCChannels = [5, 21, 37, 53, 69, 85, 101, 117, 133, 149, 165, 181, 197, 213, 229]

    // MARK: Public API

    static func analyze(networks: [NetworkModel]) -> AnalysisReport {
        guard !networks.isEmpty else { return .empty }

        var metrics: [String: NetworkMetrics] = [:]
        metrics.reserveCapacity(networks.count)

        for network in networks {
            metrics[network.id] = metricsFor(network, among: networks)
        }

        let bands = reportableBands(in: networks)
        var recommendations: [WiFiBand: [ChannelRecommendation]] = [:]
        for band in bands {
            recommendations[band] = self.recommendations(for: band, among: networks)
        }

        let findings = metrics.values
            .flatMap { metric -> [SecurityFinding] in
                guard let network = networks.first(where: { $0.id == metric.networkId }) else { return [] }
                return metric.securityIssues.map { issue in
                    SecurityFinding(
                        id: "\(metric.networkId)-\(issue.id)",
                        networkId: metric.networkId,
                        ssid: network.displaySSID,
                        bssid: network.bssid,
                        severity: issue.severity,
                        title: issue.title,
                        detail: issue.detail
                    )
                }
            }
            .sorted {
                if $0.severity != $1.severity { return $0.severity > $1.severity }
                return $0.ssid.localizedCaseInsensitiveCompare($1.ssid) == .orderedAscending
            }

        let average =
            metrics.isEmpty
            ? 0
            : Int(round(Double(metrics.values.reduce(0) { $0 + $1.qualityScore }) / Double(metrics.count)))

        return AnalysisReport(
            metricsByNetworkId: metrics,
            recommendationsByBand: recommendations,
            securityFindings: findings,
            occupancy: occupancy(for: networks),
            averageQuality: average,
            analyzedNetworkCount: metrics.count
        )
    }

    static func metricsFor(_ network: NetworkModel, among networks: [NetworkModel]) -> NetworkMetrics {
        let sameBand = networks.filter { $0.band == network.band && $0.id != network.id }
        var load = 0.0
        var overlapping = 0
        var coChannel = 0

        for other in sameBand {
            let fraction = overlapFraction(network, other)
            guard fraction > 0 else { continue }
            overlapping += 1
            if other.channel == network.channel { coChannel += 1 }
            load += fraction * strengthWeight(rssi: other.signal) * utilizationMultiplier(other)
        }

        load = min(1.0, load)
        let congestion = max(0, min(100, Int(round((1.0 - load) * 100.0))))
        let signal = signalScore(rssi: network.signal)
        let snr = network.snr.map(snrScore)
        let utilization = network.channelUtilization.map { max(0, 100 - $0) }
        let security = securityScore(for: network)

        // Weighted blend, normalised over the sub-scores that are available.
        var weighted = Double(signal) * 0.45 + Double(congestion) * 0.25 + Double(security) * 0.10
        var weight = 0.80
        if let snr {
            weighted += Double(snr) * 0.15
            weight += 0.15
        }
        if let utilization {
            weighted += Double(utilization) * 0.10
            weight += 0.10
        }
        let quality = max(0, min(100, Int(round(weighted / weight))))

        var issues: [NetworkIssue] = []
        let securityLower = network.security.lowercased()

        if securityLower.contains("open") {
            issues.append(
                NetworkIssue(
                    id: "open",
                    severity: .critical,
                    category: .security,
                    title: "Open network",
                    detail: "Traffic is not encrypted. Avoid signing in or sending sensitive data."
                ))
        } else if securityLower.contains("wep") {
            issues.append(
                NetworkIssue(
                    id: "wep",
                    severity: .critical,
                    category: .security,
                    title: "WEP encryption",
                    detail: "WEP is broken and can be cracked in minutes. Upgrade the access point."
                ))
        } else if securityLower.contains("wpa ") {
            issues.append(
                NetworkIssue(
                    id: "wpa1",
                    severity: .warning,
                    category: .security,
                    title: "Legacy WPA",
                    detail: "WPA with TKIP is deprecated. Use WPA2 or WPA3."
                ))
        }

        if network.wpsEnabled == true {
            issues.append(
                NetworkIssue(
                    id: "wps",
                    severity: .warning,
                    category: .security,
                    title: "WPS enabled",
                    detail: "Wi-Fi Protected Setup is enabled and may be vulnerable to brute-force attacks."
                ))
        }

        if network.pmfRequired == false,
            securityLower.contains("wpa2") || securityLower.contains("wpa3")
        {
            issues.append(
                NetworkIssue(
                    id: "pmf",
                    severity: .info,
                    category: .security,
                    title: "No management frame protection",
                    detail: "PMF (802.11w) is not required, so management frames are not protected."
                ))
        }

        if network.signal <= -75 {
            issues.append(
                NetworkIssue(
                    id: "weak",
                    severity: .warning,
                    category: .performance,
                    title: "Weak signal",
                    detail: "RSSI \(network.signal) dBm is below the usable threshold for reliable voice and video."
                ))
        }

        if load >= 0.50 {
            issues.append(
                NetworkIssue(
                    id: "congested",
                    severity: load >= 0.80 ? .critical : .warning,
                    category: .performance,
                    title: "Congested channel",
                    detail: "\(overlapping) overlapping AP\(overlapping == 1 ? "" : "s") compete for airtime."
                ))
        }

        issues.sort { $0.severity > $1.severity }

        return NetworkMetrics(
            networkId: network.id,
            qualityScore: quality,
            signalScore: signal,
            snrScore: snr,
            congestionScore: congestion,
            utilizationScore: utilization,
            securityScore: security,
            coChannelCount: coChannel,
            overlappingCount: overlapping,
            interferenceLoad: load,
            issues: issues
        )
    }

    static func recommendations(
        for band: WiFiBand,
        among networks: [NetworkModel],
        limit: Int = 3
    ) -> [ChannelRecommendation] {
        let bandNetworks = networks.filter { $0.band == band }
        let candidates = candidateChannels(for: band)

        let scored = candidates.map { candidate -> ChannelRecommendation in
            var load = 0.0
            var overlapping = 0
            var coChannel = 0

            for network in bandNetworks {
                let fraction = overlapFraction(
                    band: band,
                    channel: candidate.channel,
                    widthMHz: candidate.widthMHz,
                    with: network
                )
                guard fraction > 0 else { continue }
                overlapping += 1
                if network.channel == candidate.channel { coChannel += 1 }
                load += fraction * strengthWeight(rssi: network.signal) * utilizationMultiplier(network)
            }

            load = min(1.0, load)
            var score = max(0, min(100, Int(round((1.0 - load) * 100.0))))
            if bandNetworks.isEmpty { score = 100 }

            let isDFS = band == .band5 && (52...144).contains(candidate.channel)
            let rationale: String
            if bandNetworks.isEmpty {
                rationale = "No \(band.label) networks detected — clear air."
            } else if score >= 85 {
                rationale = "Clean \(candidate.widthMHz) MHz channel with minimal overlap."
            } else if score >= 60 {
                rationale = "Moderate overlap from \(overlapping) AP\(overlapping == 1 ? "" : "s"); still usable."
            } else {
                rationale = "Busy channel — \(overlapping) overlapping AP\(overlapping == 1 ? "" : "s")."
            }

            return ChannelRecommendation(
                band: band,
                channel: candidate.channel,
                widthMHz: candidate.widthMHz,
                score: score,
                overlappingCount: overlapping,
                coChannelCount: coChannel,
                isDFS: isDFS,
                rationale: isDFS ? rationale + " DFS channel requires CAC." : rationale
            )
        }

        return Array(
            scored.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.widthMHz != rhs.widthMHz { return lhs.widthMHz > rhs.widthMHz }
                return lhs.channel < rhs.channel
            }.prefix(limit))
    }

    // MARK: Scoring primitives

    static func signalScore(rssi: Int) -> Int {
        interpolate(
            Double(rssi),
            points: [
                (-95, 0), (-90, 10), (-85, 22), (-80, 38), (-75, 52),
                (-70, 66), (-65, 78), (-60, 88), (-55, 95), (-50, 100),
            ])
    }

    static func snrScore(snr: Int) -> Int {
        interpolate(
            Double(snr),
            points: [
                (0, 0), (5, 15), (10, 32), (15, 50), (20, 66),
                (25, 80), (30, 90), (35, 96), (40, 100),
            ])
    }

    static func securityScore(for network: NetworkModel) -> Int {
        let security = network.security.lowercased()
        var base: Int
        switch true {
        case security.contains("wpa3"): base = 100
        case security.contains("owe"): base = 95
        case security.contains("wpa2"): base = 82
        case security.contains("wpa"): base = 55
        case security.contains("wep"): base = 15
        case security.contains("open"): base = 0
        default: base = 50
        }
        if security.contains("enterprise") { base += 3 }
        if network.pmfRequired == true { base += 2 }
        if network.wpsEnabled == true { base -= 12 }
        return max(0, min(100, base))
    }

    static func overlapFraction(_ first: NetworkModel, _ second: NetworkModel) -> Double {
        guard first.band == second.band else { return 0 }
        return overlapFraction(
            band: first.band,
            channel: first.channel,
            widthMHz: first.channelWidthMHz,
            with: second
        )
    }

    static func overlapFraction(
        band: WiFiBand,
        channel: Int,
        widthMHz: Int,
        with network: NetworkModel
    ) -> Double {
        guard let candidateSpan = spanMHz(band: band, channel: channel, widthMHz: widthMHz),
            let networkSpan = spanMHz(
                band: network.band,
                channel: network.channel,
                widthMHz: network.channelWidthMHz
            )
        else { return 0 }
        let overlap = max(
            0,
            min(candidateSpan.upperBound, networkSpan.upperBound)
                - max(candidateSpan.lowerBound, networkSpan.lowerBound))
        let smaller = min(
            candidateSpan.upperBound - candidateSpan.lowerBound,
            networkSpan.upperBound - networkSpan.lowerBound)
        guard smaller > 0 else { return 0 }
        return min(1, overlap / smaller)
    }

    static func spanMHz(band: WiFiBand, channel: Int, widthMHz: Int) -> ClosedRange<Double>? {
        guard channel > 0 else { return nil }
        let center: Double
        switch band {
        case .band24:
            center = channel == 14 ? 2484 : 2407 + Double(channel) * 5
        case .band5:
            center = 5000 + Double(channel) * 5
        case .band6:
            center = 5950 + Double(channel) * 5
        case .unknown:
            return nil
        }
        let width = Double(max(20, widthMHz))
        return (center - width / 2)...(center + width / 2)
    }

    static func candidateChannels(for band: WiFiBand) -> [Candidate] {
        switch band {
        case .band24:
            return ghz24Channels.map { Candidate(channel: $0, widthMHz: 20) }
        case .band5:
            let narrow = ghz5Channels.map { Candidate(channel: $0, widthMHz: 20) }
            let wide = [36, 52, 100, 116, 132, 149].map { Candidate(channel: $0, widthMHz: 80) }
            return narrow + wide
        case .band6:
            let narrow = ghz6PSCChannels.map { Candidate(channel: $0, widthMHz: 20) }
            let wide = [7, 23, 39, 55, 71, 87, 103, 119, 135, 151].map { Candidate(channel: $0, widthMHz: 80) }
            return narrow + wide
        case .unknown:
            return []
        }
    }

    // MARK: Helpers

    private static func reportableBands(in networks: [NetworkModel]) -> [WiFiBand] {
        var bands: [WiFiBand] = [.band24, .band5]
        if networks.contains(where: { $0.band == .band6 }) { bands.append(.band6) }
        return bands
    }

    private static func occupancy(for networks: [NetworkModel]) -> [ChannelOccupancy] {
        struct Key: Hashable {
            let band: WiFiBand
            let channel: Int
        }

        var groups: [Key: [NetworkModel]] = [:]
        for network in networks where network.band != .unknown && network.channel > 0 {
            groups[Key(band: network.band, channel: network.channel), default: []].append(network)
        }

        return groups.map { key, group in
            let signals = group.map(\.signal)
            let strongest = signals.max() ?? 0
            let average = signals.isEmpty ? 0 : Int(round(Double(signals.reduce(0, +)) / Double(signals.count)))
            return ChannelOccupancy(
                band: key.band,
                channel: key.channel,
                networkCount: group.count,
                strongestRSSI: strongest,
                averageRSSI: average
            )
        }.sorted { lhs, rhs in
            if lhs.band != rhs.band { return lhs.band.rawValue < rhs.band.rawValue }
            return lhs.channel < rhs.channel
        }
    }

    private static func strengthWeight(rssi: Int) -> Double {
        max(0.05, min(1.0, (Double(rssi) + 100.0) / 60.0))
    }

    private static func utilizationMultiplier(_ network: NetworkModel) -> Double {
        guard let utilization = network.channelUtilization else { return 0.7 }
        return 0.5 + Double(max(0, min(100, utilization))) / 100.0
    }

    private static func interpolate(_ value: Double, points: [(Double, Double)]) -> Int {
        guard let first = points.first, let last = points.last else { return 0 }
        if value <= first.0 { return Int(first.1) }
        if value >= last.0 { return Int(last.1) }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            guard value <= current.0 else { continue }
            let span = current.0 - previous.0
            guard span > 0 else { return Int(current.1) }
            let ratio = (value - previous.0) / span
            return Int(round(previous.1 + ratio * (current.1 - previous.1)))
        }
        return Int(last.1)
    }
}
