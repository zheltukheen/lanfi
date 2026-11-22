import Foundation

/// One gateway echo attempt while a walk test runs. The probe is what turns a
/// BSSID transition into a measured roam: without it the monitor can only say
/// that the link changed, not how long it was gone.
struct RoamProbeSample: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let reached: Bool
    let latencyMilliseconds: Double?

    init(id: UUID = UUID(), at: Date, reached: Bool, latencyMilliseconds: Double?) {
        self.id = id
        self.at = at
        self.reached = reached
        self.latencyMilliseconds = latencyMilliseconds
    }
}

/// Packet loss and reconnect time around one BSSID transition.
struct RoamImpact: Identifiable, Equatable {
    let transitionID: String
    let packetLossPercent: Double
    let reconnectMilliseconds: Int?
    let probes: Int

    var id: String { transitionID }
}

enum RoamProbeAnalyzer {
    /// Probes this close to the transition belong to the roam.
    static let window: TimeInterval = 3
    /// Fewer probes than this cannot describe a roam honestly.
    static let minimumProbes = 2

    static func impact(
        for transition: RoamTransition, probes: [RoamProbeSample],
        window: TimeInterval = window
    ) -> RoamImpact? {
        let inWindow = probes.filter {
            $0.at >= transition.at.addingTimeInterval(-window)
                && $0.at <= transition.at.addingTimeInterval(window)
        }
        guard inWindow.count >= minimumProbes else { return nil }
        let lost = inWindow.filter { !$0.reached }.count
        let loss = Double(lost) / Double(inWindow.count) * 100

        let lastBefore = probes.last { $0.reached && $0.at <= transition.at }
        let firstAfter = probes.first { $0.reached && $0.at > transition.at }
        var reconnect: Int?
        if let lastBefore, let firstAfter {
            let milliseconds = firstAfter.at.timeIntervalSince(lastBefore.at) * 1000
            if milliseconds >= 0, milliseconds < 60_000 {
                reconnect = Int(milliseconds.rounded())
            }
        }

        return RoamImpact(
            transitionID: transition.id,
            packetLossPercent: loss,
            reconnectMilliseconds: reconnect,
            probes: inWindow.count
        )
    }

    static func impacts(
        transitions: [RoamTransition], probes: [RoamProbeSample]
    ) -> [RoamImpact] {
        transitions.compactMap { impact(for: $0, probes: probes) }
    }
}
