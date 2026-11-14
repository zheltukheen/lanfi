import Foundation

/// EAPOL-Key traffic observed in an offline capture. LanFi only reports what
/// the air already carried: it never frames, injects or deauthenticates.
struct EAPOLHandshake: Identifiable, Equatable {
    let bssid: String
    var keyFrameCount: Int
    /// EAPOL-Key messages 1…4 seen for this BSSID.
    var messages: Set<Int>
    var hasPMKID: Bool
    var firstSeen: Date
    var lastSeen: Date

    var id: String { bssid }

    /// Message 2 supplies the SNonce and MIC; message 1 (or 3) supplies the
    /// ANonce. Together they are what an offline dictionary attack needs.
    var hasCompleteHandshake: Bool {
        messages.contains(2) && (messages.contains(1) || messages.contains(3))
    }

    var messageLabel: String {
        guard !messages.isEmpty else { return "—" }
        return messages.sorted().map(String.init).joined(separator: ",")
    }
}

/// Per-BSSID management-frame counters. Deauthentication and disassociation
/// frames are a normal part of roaming, so only a burst is suspicious; the
/// counter also explains a client that keeps dropping off the network.
struct ManagementCounters: Identifiable, Equatable {
    struct Reason: Identifiable, Equatable {
        let code: Int
        var count: Int

        var id: Int { code }
        var label: String { ReasonCodeCatalog.label(code) }
    }

    let bssid: String
    var beacons: Int = 0
    var probeResponses: Int = 0
    var deauth: Int = 0
    var disassoc: Int = 0
    var burst: Bool = false
    var reasons: [Reason] = []
    var firstSeen: Date?
    var lastSeen: Date?

    var id: String { bssid }
    var disruptionCount: Int { deauth + disassoc }
}

/// The 802.11 reason codes that show up in a survey capture, with short text.
enum ReasonCodeCatalog {
    private static let labels: [Int: String] = [
        1: String(localized: "Unspecified"),
        2: String(localized: "Previous authentication no longer valid"),
        3: String(localized: "Station is leaving the network"),
        4: String(localized: "Inactivity"),
        5: String(localized: "AP cannot handle all stations"),
        6: String(localized: "Class 2 frame from unauthenticated station"),
        7: String(localized: "Class 3 frame from unassociated station"),
        8: String(localized: "Station left"),
        9: String(localized: "Station is not authenticated"),
        15: String(localized: "4-way handshake timeout"),
        16: String(localized: "Group key handshake timeout"),
        17: String(localized: "Handshake element mismatch"),
        18: String(localized: "Invalid group cipher"),
        19: String(localized: "Invalid pairwise cipher"),
        20: String(localized: "Invalid AKMP"),
        23: String(localized: "802.1X authentication failed"),
        34: String(localized: "Disassociated because the AP is busy"),
    ]

    static func label(_ code: Int) -> String {
        labels[code] ?? String(format: String(localized: "Reason %d"), code)
    }
}

/// One security observation about a capture. Mirrors the graded findings of
/// the live security audit, but is derived from frames instead of beacons.
struct CaptureFinding: Identifiable, Equatable {
    enum Severity: Int, Comparable, Equatable {
        case info = 0
        case warning = 1
        case critical = 2

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .info: return String(localized: "Info")
            case .warning: return String(localized: "Warning")
            case .critical: return String(localized: "Critical")
            }
        }

        var symbol: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let bssid: String?
}

struct CaptureSecurityReport: Equatable {
    var handshakes: [EAPOLHandshake] = []
    var management: [ManagementCounters] = []
    var findings: [CaptureFinding] = []

    static let empty = CaptureSecurityReport()

    var isEmpty: Bool {
        handshakes.isEmpty && management.isEmpty && findings.isEmpty
    }

    var completeHandshakeCount: Int {
        handshakes.filter(\.hasCompleteHandshake).count
    }

    var pmkidCount: Int {
        handshakes.filter(\.hasPMKID).count
    }

    var deauthTotal: Int {
        management.reduce(0) { $0 + $1.deauth }
    }

    var disassocTotal: Int {
        management.reduce(0) { $0 + $1.disassoc }
    }

    var burstCount: Int {
        management.filter(\.burst).count
    }

    var criticalCount: Int {
        findings.filter { $0.severity == .critical }.count
    }

    func handshake(for bssid: String) -> EAPOLHandshake? {
        handshakes.first { $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame }
    }

    func counters(for bssid: String) -> ManagementCounters? {
        management.first { $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame }
    }
}

/// Turns raw frame tallies into the graded findings the capture UI shows.
/// Pure logic: `PcapAnalyzer` does the byte-level work, this decides what it
/// means. No CoreWLAN or SwiftUI, so tests can compile it headless.
enum CaptureSecurityAnalyzer {
    static let burstWindow: TimeInterval = 5
    static let burstThreshold = 8
    static let beaconFloodBSSIDThreshold = 5

    static func report(
        handshakes: [EAPOLHandshake],
        counters: [ManagementCounters],
        beacons: [CapturedBeacon] = [],
        deauthTimes: [String: [Date]] = [:]
    ) -> CaptureSecurityReport {
        var counters = counters
        for index in counters.indices {
            counters[index].burst = burstDetected(
                times: deauthTimes[counters[index].bssid.uppercased()] ?? [])
        }
        var report = CaptureSecurityReport(handshakes: handshakes, management: counters)

        let securityByBSSID = Dictionary(
            beacons.map { ($0.bssid.uppercased(), $0.security) }, uniquingKeysWith: { first, _ in first })
        let ssidByBSSID = Dictionary(
            beacons.map { ($0.bssid.uppercased(), $0.ssid) }, uniquingKeysWith: { first, _ in first })

        for handshake in handshakes.sorted(by: { $0.bssid < $1.bssid }) {
            let bssid = handshake.bssid.uppercased()
            let security = securityByBSSID[bssid]
            let target = "\(ssidByBSSID[bssid] ?? String(localized: "unknown SSID")) (\(handshake.bssid))"
            let offlineCrackable = isOfflineCrackable(security: security, pmkid: handshake.hasPMKID)

            if handshake.hasPMKID {
                report.findings.append(
                    CaptureFinding(
                        id: "pmkid-\(bssid)",
                        severity: offlineCrackable ? .critical : .info,
                        title: String(localized: "PMKID in capture"),
                        detail: offlineCrackable
                            ? String(
                                localized:
                                    "A PMKID for \(target) was captured from a single frame, with no client present. A weak passphrase can be recovered offline. Use WPA3-SAE or a long random passphrase."
                            )
                            : String(
                                localized:
                                    "A PMKID for \(target) was captured. This network advertises SAE or 802.1X, so an offline dictionary attack against the passphrase does not apply."
                            ),
                        bssid: handshake.bssid
                    ))
            }

            if handshake.hasCompleteHandshake {
                report.findings.append(
                    CaptureFinding(
                        id: "handshake-\(bssid)",
                        severity: offlineCrackable ? .warning : .info,
                        title: String(localized: "4-way handshake captured"),
                        detail: offlineCrackable
                            ? String(
                                localized:
                                    "The capture holds messages \(handshake.messageLabel) for \(target) — enough for an offline dictionary attack. A long passphrase or WPA3-SAE removes that risk."
                            )
                            : String(
                                localized:
                                    "The capture holds messages \(handshake.messageLabel) for \(target). This network advertises SAE or 802.1X, so the exchange cannot be attacked offline with a wordlist."
                            ),
                        bssid: handshake.bssid
                    ))
            }
        }

        for counter in counters.sorted(by: { $0.disruptionCount > $1.disruptionCount }) {
            let reasons = reasonSummary(counter.reasons)
            if counter.burst || counter.disruptionCount >= burstThreshold {
                report.findings.append(
                    CaptureFinding(
                        id: "deauth-\(counter.bssid)",
                        severity: .critical,
                        title: String(localized: "Deauthentication burst"),
                        detail: String(
                            localized:
                                "\(counter.disruptionCount) deauth/disassoc frames from \(counter.bssid) within seconds\(reasons). That is either a management-frame flood or a client whose driver keeps resetting; both drop every client on the BSSID."
                        ),
                        bssid: counter.bssid
                    ))
            } else if counter.disruptionCount > 0 {
                report.findings.append(
                    CaptureFinding(
                        id: "deauth-\(counter.bssid)",
                        severity: .info,
                        title: String(localized: "Deauthentication frames observed"),
                        detail: String(
                            localized:
                                "\(counter.disruptionCount) deauth/disassoc frames from \(counter.bssid)\(reasons). Normal for roaming or a sleeping client; a burst would be a flood."
                        ),
                        bssid: counter.bssid
                    ))
            }
        }

        for (ssid, count) in beaconFloodCandidates(beacons: beacons) {
            report.findings.append(
                CaptureFinding(
                    id: "beacon-flood-\(ssid)",
                    severity: .warning,
                    title: String(localized: "Possible beacon flood"),
                    detail: String(
                        localized:
                            "\(count) BSSIDs with randomized MAC addresses advertise the SSID \(ssid). Beacon flooding is used to confuse scanners and client steering; compare the BSSIDs you trust."
                    ),
                    bssid: nil
                ))
        }

        report.findings.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.title < rhs.title
        }
        return report
    }

    /// A handshake is only worth flagging when the network still relies on a
    /// passphrase. SAE and 802.1X networks use a per-session key exchange.
    static func isOfflineCrackable(security: String?, pmkid: Bool) -> Bool {
        guard let security else { return true }
        let lower = security.lowercased()
        if lower.contains("sae") && !lower.contains("transition") && !lower.contains("psk") {
            return false
        }
        if lower.contains("enterprise") { return false }
        if lower.contains("open") || lower.contains("owe") { return false }
        if lower.contains("wpa3") && !lower.contains("transition") { return false }
        return true
    }

    static func burstDetected(times: [Date]) -> Bool {
        guard times.count >= burstThreshold else { return false }
        let sorted = times.sorted()
        for index in 0..<(sorted.count - burstThreshold + 1) {
            let window = sorted[index + burstThreshold - 1].timeIntervalSince(sorted[index])
            if window <= burstWindow { return true }
        }
        return false
    }

    private static func reasonSummary(_ reasons: [ManagementCounters.Reason]) -> String {
        guard !reasons.isEmpty else { return "" }
        let parts = reasons.prefix(3).map { "\($0.label) ×\($0.count)" }
        return " (" + parts.joined(separator: ", ") + ")"
    }

    /// Many randomized BSSIDs sharing one SSID: the signature of a beacon
    /// flood. Real infrastructure uses registered (burned-in) addresses.
    static func beaconFloodCandidates(beacons: [CapturedBeacon]) -> [(String, Int)] {
        var bssidsBySSID: [String: Set<String>] = [:]
        for beacon in beacons {
            let ssid = beacon.ssid
            guard !ssid.isEmpty, ssid != "Hidden" else { continue }
            guard isRandomizedMAC(beacon.bssid) else { continue }
            bssidsBySSID[ssid, default: []].insert(beacon.bssid.uppercased())
        }
        return
            bssidsBySSID
            .filter { $0.value.count >= beaconFloodBSSIDThreshold }
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }

    static func isRandomizedMAC(_ mac: String) -> Bool {
        let hex = mac.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "")
        guard hex.count >= 2, let first = UInt8(hex.prefix(2), radix: 16) else { return false }
        return first & 0x02 != 0
    }
}
