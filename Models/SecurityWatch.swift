import Foundation

/// Security class of a BSSID, ordered from least to most protection.
///
/// Used only for relative comparison inside one SSID: an AP group that mixes
/// WPA3 with an open BSSID is suspicious, while every radio of the group using
/// the same security is normal multi-band infrastructure.
enum WSSecurityClass: Comparable {
    case unknown
    case open
    case wep
    case legacyWPA
    case wpa2
    case owe
    case wpa3
    case enterprise

    /// Relative strength; OWE is unauthenticated but encrypted, so it ranks
    /// with WPA2 rather than with the open class.
    var rank: Int {
        switch self {
        case .unknown: return -1
        case .open: return 0
        case .wep: return 1
        case .legacyWPA: return 2
        case .wpa2, .owe: return 3
        case .wpa3: return 4
        case .enterprise: return 5
        }
    }

    static func < (lhs: WSSecurityClass, rhs: WSSecurityClass) -> Bool {
        lhs.rank < rhs.rank
    }

    static func classify(_ security: String) -> WSSecurityClass {
        let value = security.lowercased()
        if value.isEmpty { return .unknown }
        if value.contains("open") || value.contains("none") { return .open }
        if value.contains("wep") { return .wep }
        if value.contains("enterprise") || value.contains("802.1x") { return .enterprise }
        if value.contains("owe") { return .owe }
        if value.contains("sae") || value.contains("wpa3") {
            // Transition mode still accepts WPA2 clients, so it is not a
            // downgrade on its own.
            if value.contains("transition") { return .wpa2 }
            return .wpa3
        }
        if value.contains("wpa2") { return .wpa2 }
        if value.contains("wpa") { return .legacyWPA }
        return .unknown
    }

    var label: String {
        switch self {
        case .open: return String(localized: "Open")
        case .wep: return String(localized: "WEP")
        case .legacyWPA: return String(localized: "Legacy WPA")
        case .wpa2: return String(localized: "WPA2")
        case .owe: return String(localized: "OWE")
        case .wpa3: return String(localized: "WPA3")
        case .enterprise: return String(localized: "Enterprise")
        case .unknown: return String(localized: "Unknown")
        }
    }

    /// True when the network still relies on a passphrase instead of SAE or
    /// 802.1X, which is what makes a twin worth investigating.
    var isPassphraseBased: Bool {
        self == .wep || self == .legacyWPA || self == .wpa2
    }
}

struct SecurityWatchAlert: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case evilTwin
        case securityDowngrade
        case randomizedBSSID
        case deauthBurst
        /// P3.7: gateway ARP and DNS answer integrity.
        case gatewayChanged
        case dnsMismatch

        var title: String {
            switch self {
            case .evilTwin: return String(localized: "Possible evil twin")
            case .securityDowngrade: return String(localized: "Security downgrade")
            case .randomizedBSSID: return String(localized: "Randomized BSSID")
            case .deauthBurst: return String(localized: "Deauthentication burst")
            case .gatewayChanged: return String(localized: "Gateway MAC changed")
            case .dnsMismatch: return String(localized: "DNS answer mismatch")
            }
        }

        var icon: String {
            switch self {
            case .evilTwin: return "wifi.exclamationmark"
            case .securityDowngrade: return "lock.slash"
            case .randomizedBSSID: return "questionmark.diamond"
            case .deauthBurst: return "bolt.trianglebadge.exclamationmark"
            case .gatewayChanged: return "exclamationmark.shield"
            case .dnsMismatch: return "questionmark.circle"
            }
        }
    }

    let id: String
    let kind: Kind
    let severity: IssueSeverity
    let ssid: String
    let bssid: String
    let detail: String
    let at: Date
}

struct SecurityWatchReport: Equatable {
    let alerts: [SecurityWatchAlert]
    let networkCount: Int
    let ssidCount: Int
    let monitoredSSIDCount: Int

    static let empty = SecurityWatchReport(
        alerts: [], networkCount: 0, ssidCount: 0, monitoredSSIDCount: 0)

    var criticalCount: Int { alerts.filter { $0.severity == .critical }.count }
    var warningCount: Int { alerts.filter { $0.severity == .warning }.count }
    var infoCount: Int { alerts.filter { $0.severity == .info }.count }

    func alerts(for kind: SecurityWatchAlert.Kind) -> [SecurityWatchAlert] {
        alerts.filter { $0.kind == kind }
    }
}

/// Read-only heuristic watch over the beacon scan and the monitor's event log.
///
/// It never frames, injects or deauthenticates; deauth alerts only appear when
/// a packet capture observed a burst, because macOS offers no passive deauth
/// feed to normal apps.
enum SecurityWatchEvaluator {
    static let deauthWindow: TimeInterval = 15 * 60
    /// Gateway/resolver findings stay visible for an hour, because one spoofed
    /// ARP reply matters until the user has looked at it.
    static let gatewayWindow: TimeInterval = 60 * 60

    static func evaluate(
        networks: [NetworkModel],
        events: [MonitorEvent] = [],
        now: Date = Date()
    ) -> SecurityWatchReport {
        var alerts: [SecurityWatchAlert] = []

        let grouped = Dictionary(
            grouping: networks.filter { !$0.ssid.isEmpty && $0.ssid != "<Hidden>" },
            by: { $0.ssid.trimmingCharacters(in: .whitespacesAndNewlines) })

        for (ssid, group) in grouped.sorted(by: { $0.key < $1.key }) {
            let classes = group.map { WSSecurityClass.classify($0.security) }
            guard let best = classes.filter({ $0 != .unknown }).max() else { continue }
            guard best >= .wpa2 else { continue }

            let bestNetworks = group.enumerated()
                .filter { classes[$0.offset] == best }
                .map(\.element)
            let siblingIDs = Set(
                bestNetworks.flatMap {
                    CoLocatedAPDetector.coLocatedSiblings(of: $0, in: group).map(\.id)
                })

            for (index, network) in group.enumerated() {
                let cls = classes[index]
                guard cls != .unknown, cls < best else { continue }
                // Radios of one chassis often differ in band only; the
                // co-location merge already proved they belong together.
                if siblingIDs.contains(network.id) { continue }

                let at = now
                // WPA2 vs WPA3 across bands is routine (transition mode, older
                // firmware on one radio) and is not worth an alert.
                if cls == .wpa2 && best == .wpa3 { continue }

                if cls <= .wep {
                    alerts.append(
                        SecurityWatchAlert(
                            id: "evil-twin-\(network.bssid)",
                            kind: .evilTwin,
                            severity: .critical,
                            ssid: ssid,
                            bssid: network.bssid,
                            detail: String(
                                localized:
                                    "This BSSID advertises \(ssid) as \(cls.label) while another BSSID of the same SSID uses \(best.label). That is the classic twin signature: clients may be steered to the weaker copy. Compare the vendor and signal, and prefer the secured BSSID."
                            ),
                            at: at))
                } else {
                    alerts.append(
                        SecurityWatchAlert(
                            id: "downgrade-\(network.bssid)",
                            kind: .securityDowngrade,
                            severity: .warning,
                            ssid: ssid,
                            bssid: network.bssid,
                            detail: String(
                                localized:
                                    "This BSSID uses \(cls.label) while another radio of \(ssid) offers \(best.label). If both belong to you, align them; if not, treat the weaker one as untrusted."
                            ),
                            at: at))
                }
            }

            let burnedIn = group.filter { !$0.bssid.isEmpty && !isRandomized($0.bssid) }
            guard !burnedIn.isEmpty else { continue }
            for network in group
            where !network.bssid.isEmpty && isRandomized(network.bssid) {
                alerts.append(
                    SecurityWatchAlert(
                        id: "randomized-\(network.bssid)",
                        kind: .randomizedBSSID,
                        severity: .warning,
                        ssid: ssid,
                        bssid: network.bssid,
                        detail: String(
                            localized:
                                "This BSSID uses a locally administered (randomized) address while the same SSID is also advertised from registered hardware addresses. Infrastructure normally uses burned-in addresses; a randomized copy can be a hotspot or a spoofing tool."
                        ),
                        at: now))
            }
        }

        // P3.7: gateway and resolver findings arrive as Monitor events and are
        // surfaced here next to the beacon heuristics.
        for event in events
        where (event.kind == .gatewayChanged || event.kind == .dnsMismatch)
            && now.timeIntervalSince(event.at) <= gatewayWindow
        {
            alerts.append(
                SecurityWatchAlert(
                    id: "\(event.kind.rawValue)-\(event.id.uuidString)",
                    kind: event.kind == .gatewayChanged ? .gatewayChanged : .dnsMismatch,
                    severity: event.kind == .gatewayChanged ? .critical : .warning,
                    ssid: event.ssid,
                    bssid: event.bssid,
                    detail: event.detail,
                    at: event.at))
        }

        for event in events
        where event.kind == .deauthBurst
            && now.timeIntervalSince(event.at) <= deauthWindow
        {
            let ssid = event.ssid.isEmpty ? String(localized: "unknown SSID") : event.ssid
            alerts.append(
                SecurityWatchAlert(
                    id: "deauth-\(event.bssid)-\(event.id.uuidString)",
                    kind: .deauthBurst,
                    severity: .critical,
                    ssid: ssid,
                    bssid: event.bssid,
                    detail: event.detail,
                    at: event.at))
        }

        alerts.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.at > rhs.at
        }

        let monitored = Set(
            alerts.map { $0.ssid }.filter { $0 != String(localized: "unknown SSID") })

        return SecurityWatchReport(
            alerts: alerts,
            networkCount: networks.count,
            ssidCount: grouped.count,
            monitoredSSIDCount: monitored.count)
    }

    static func isRandomized(_ bssid: String) -> Bool {
        CaptureSecurityAnalyzer.isRandomizedMAC(bssid)
    }
}
