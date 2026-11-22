import Foundation

/// P2 — counters that update while a capture is still being written, instead
/// of only after the pcap is analyzed. The numbers come from the same
/// `CaptureSecurityReport` used offline, recalculated over the growing file.
struct LiveThreatSnapshot: Equatable {
    var framesParsed = 0
    var deauth = 0
    var disassoc = 0
    var eapolKeyFrames = 0
    var handshakes = 0
    var completeHandshakes = 0
    var pmkids = 0
    var bursts = 0
    var bytes = 0
    var updatedAt: Date?

    static let empty = LiveThreatSnapshot()

    var isEmpty: Bool {
        framesParsed == 0 && deauth == 0 && disassoc == 0 && eapolKeyFrames == 0
    }

    var disruptionTotal: Int { deauth + disassoc }

    static func make(
        report: CaptureSecurityReport, bytes: Int, at date: Date = Date()
    ) -> LiveThreatSnapshot {
        LiveThreatSnapshot(
            framesParsed: report.management.reduce(0) {
                $0 + $1.beacons + $1.probeResponses + $1.deauth + $1.disassoc
            },
            deauth: report.deauthTotal,
            disassoc: report.disassocTotal,
            eapolKeyFrames: report.handshakes.reduce(0) { $0 + $1.keyFrameCount },
            handshakes: report.handshakes.count,
            completeHandshakes: report.completeHandshakeCount,
            pmkids: report.pmkidCount,
            bursts: report.burstCount,
            bytes: bytes,
            updatedAt: date
        )
    }
}

enum LiveThreatPresentation {
    static func counter(_ value: Int) -> String { "\(value)" }
}
