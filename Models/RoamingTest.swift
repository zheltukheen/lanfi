import Foundation

/// Which fast-roaming standards the connected BSSID advertises.
struct RoamingCapabilities: Equatable {
    /// 802.11r — Fast BSS Transition (advertised as the MDIE/Mobility Domain or
    /// the Fast Transition field CoreWLAN exposes).
    let fastTransition: Bool
    /// 802.11k — Radio Measurements (RM Enabled Capabilities, IE 70).
    let radioMeasurements: Bool
    /// 802.11v — BSS Transition Management (Mobility Domain, IE 54).
    let bssTransition: Bool

    var supportedCount: Int {
        [fastTransition, radioMeasurements, bssTransition].filter { $0 }.count
    }

    var summary: String {
        var items: [String] = []
        if fastTransition { items.append("802.11r") }
        if radioMeasurements { items.append("802.11k") }
        if bssTransition { items.append("802.11v") }
        return items.isEmpty ? "None advertised" : items.joined(separator: " · ")
    }
}

struct RoamTransition: Identifiable, Equatable {
    let id: String
    let at: Date
    let fromBSSID: String
    let toBSSID: String
    let rssiBefore: Int
    let rssiAfter: Int

    var strengthDelta: Int { rssiAfter - rssiBefore }

    /// Same rule the monitor uses for roaming failures: landing on a weak link
    /// or losing more than 10 dB.
    var isFailure: Bool { rssiAfter <= -80 || strengthDelta <= -10 }
}

struct RoamingVerdict: Identifiable, Equatable {
    enum Kind: String {
        case sticky
        case bandSteering
        case weak
    }

    let kind: Kind
    let title: String
    let detail: String

    var id: String { kind.rawValue }
}

struct RoamingAssessment: Equatable {
    let ssid: String
    let bssid: String
    let rssi: Int
    let capabilities: RoamingCapabilities
    let transitions: [RoamTransition]
    let failureCount: Int
    let verdicts: [RoamingVerdict]
    let lastRoamAt: Date?

    var isSticky: Bool { verdicts.contains { $0.kind == .sticky } }
}

enum RoamingAnalyzer {
    static let weakLinkThreshold = -75
    static let stickyAdvantageDb = 10
    static let steeringAdvantageDb = 6

    static func capabilities(for network: NetworkModel) -> RoamingCapabilities {
        let elementIds = Set(network.informationElements.map(\.elementId))
        return RoamingCapabilities(
            fastTransition: network.fastTransition == true,
            radioMeasurements: elementIds.contains(70),
            bssTransition: elementIds.contains(54)
        )
    }

    /// One transition per BSSID change in the connected-link samples.
    static func transitions(from samples: [MonitorSample]) -> [RoamTransition] {
        let ordered = samples.sorted { $0.at < $1.at }
        guard ordered.count > 1 else { return [] }
        var result: [RoamTransition] = []
        for index in 1..<ordered.count {
            let previous = ordered[index - 1]
            let current = ordered[index]
            guard previous.bssid != current.bssid else { continue }
            result.append(
                RoamTransition(
                    id: "\(index)-\(current.bssid)-\(current.at.timeIntervalSince1970)",
                    at: current.at,
                    fromBSSID: previous.bssid,
                    toBSSID: current.bssid,
                    rssiBefore: previous.rssi,
                    rssiAfter: current.rssi
                ))
        }
        return result
    }

    static func verdicts(
        connected: NetworkModel?, visible: [NetworkModel]
    ) -> [RoamingVerdict] {
        guard let connected else { return [] }
        var items: [RoamingVerdict] = []

        if connected.signal <= weakLinkThreshold {
            let better = candidates(
                for: connected, in: visible, minimumAdvantage: stickyAdvantageDb
            ).first
            if let better {
                items.append(
                    RoamingVerdict(
                        kind: .sticky,
                        title: String(localized: "Sticky client"),
                        detail: String(
                            localized:
                                "Connected at \(connected.signal) dBm while \(better.bssid) on channel \(better.channel) is \(better.signal) dBm. The client should have roamed."
                        )))
            } else {
                items.append(
                    RoamingVerdict(
                        kind: .weak,
                        title: String(localized: "Weak link"),
                        detail: String(
                            localized:
                                "Connected at \(connected.signal) dBm with no stronger BSSID of this network in range."
                        )))
            }
        }

        if connected.band == .band24 {
            let steering = visible.filter {
                $0.id != connected.id && $0.ssid == connected.ssid
                    && ($0.band == .band5 || $0.band == .band6)
                    && $0.signal >= connected.signal + steeringAdvantageDb
            }.sorted { $0.signal > $1.signal }.first
            if let steering {
                items.append(
                    RoamingVerdict(
                        kind: .bandSteering,
                        title: String(localized: "Band steering opportunity"),
                        detail: String(
                            localized:
                                "A \(steering.bandLabel) radio of this network is \(steering.signal - connected.signal) dB stronger on channel \(steering.channel)."
                        )))
            }
        }

        return items
    }

    static func candidates(
        for connected: NetworkModel, in visible: [NetworkModel], minimumAdvantage: Int
    ) -> [NetworkModel] {
        visible
            .filter {
                $0.id != connected.id && $0.ssid == connected.ssid && !$0.bssid.isEmpty
                    && $0.signal >= connected.signal + minimumAdvantage
            }
            .sorted { $0.signal > $1.signal }
    }

    static func assess(
        connected: NetworkModel?, visible: [NetworkModel], samples: [MonitorSample],
        now: Date = Date()
    ) -> RoamingAssessment? {
        guard let connected else { return nil }
        let transitions = transitions(from: samples)
        let failures = transitions.filter(\.isFailure).count
        return RoamingAssessment(
            ssid: connected.displaySSID,
            bssid: connected.bssid,
            rssi: connected.signal,
            capabilities: capabilities(for: connected),
            transitions: transitions,
            failureCount: failures,
            verdicts: verdicts(connected: connected, visible: visible),
            lastRoamAt: transitions.last?.at
        )
    }
}
