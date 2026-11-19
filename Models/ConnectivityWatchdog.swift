import Foundation
import LanFiCore

/// P3.3 — Connectivity watchdog.
///
/// A working Wi-Fi link can still have a dead WAN, so the menu bar has to answer
/// "is the internet working right now?" instead of only reflecting the last
/// diagnostics run. Everything here is pure: the service owns the timer and the
/// probes, and these values decide what the probe results mean.
enum ConnectivityVerdict: String, CaseIterable, Codable, Sendable {
    case unknown
    case online
    case captivePortal
    case offline

    var title: String {
        switch self {
        case .unknown: return String(localized: "Not checked yet")
        case .online: return String(localized: "Online")
        case .captivePortal: return String(localized: "Captive portal")
        case .offline: return String(localized: "Offline")
        }
    }

    /// A captive portal is reachable but not usable, so it is not "online".
    var isOnline: Bool { self == .online }

    var alertBody: String {
        switch self {
        case .online: return String(localized: "Internet is back.")
        case .captivePortal: return String(localized: "A captive portal is intercepting traffic. Sign in to continue.")
        case .offline: return String(localized: "The internet is unreachable.")
        case .unknown: return ""
        }
    }
}

/// One reduced HTTPS/HTTP probe result.
struct ConnectivityProbeOutcome: Equatable, Sendable {
    var statusCode: Int?
    var redirected: Bool
    var body: String
    var latencyMilliseconds: Int?
    var didFail: Bool

    static let failure = ConnectivityProbeOutcome(
        statusCode: nil, redirected: false, body: "", latencyMilliseconds: nil, didFail: true)

    init(
        statusCode: Int?, redirected: Bool, body: String, latencyMilliseconds: Int?,
        didFail: Bool = false
    ) {
        self.statusCode = statusCode
        self.redirected = redirected
        self.body = body
        self.latencyMilliseconds = latencyMilliseconds
        self.didFail = didFail
    }
}

/// Maps a probe result to a verdict.
///
/// The captive-portal endpoint answers `200 Success` on a healthy network; a
/// portal answers with its own HTML or redirects, and an unreachable WAN fails
/// outright. A plain 2xx from a user-configured URL counts as online, because
/// only the captive endpoint promises the `Success` marker.
enum ConnectivityProbeClassifier {
    static let successMarker = "Success"

    static func classify(_ outcome: ConnectivityProbeOutcome) -> ConnectivityVerdict {
        guard !outcome.didFail, let status = outcome.statusCode else { return .offline }
        if outcome.redirected { return .captivePortal }
        if (300..<400).contains(status) { return .captivePortal }
        guard (200..<300).contains(status) else { return .offline }
        if outcome.body.contains(successMarker) { return .online }
        if outcome.body.localizedCaseInsensitiveContains("<html") { return .captivePortal }
        return .online
    }
}

/// Tri-state verdict with hysteresis: one failed probe never flips a working
/// connection to "offline", because a single dropped request is normal.
struct ConnectivityWatchdogMachine: Equatable {
    static let failuresBeforeOffline = 2

    struct Change: Equatable, Sendable {
        let from: ConnectivityVerdict
        let to: ConnectivityVerdict
    }

    private(set) var verdict: ConnectivityVerdict = .unknown
    private(set) var consecutiveFailures = 0
    private(set) var lastCheckedAt: Date?
    private(set) var latencyMilliseconds: Int?
    private(set) var lastChangedAt: Date?

    /// Records one sample and returns the verdict change, if the state moved.
    ///
    /// `pathReachable` is `NWPathMonitor`'s answer; `false` means the link is
    /// gone, which is an immediate offline verdict rather than a failed probe.
    @discardableResult
    mutating func record(
        pathReachable: Bool?, probe: ConnectivityProbeOutcome?, at date: Date
    ) -> Change? {
        lastCheckedAt = date

        let candidate: ConnectivityVerdict
        if pathReachable == false {
            candidate = .offline
        } else if let probe {
            candidate = ConnectivityProbeClassifier.classify(probe)
        } else {
            candidate = .offline
        }

        if candidate == .offline {
            if pathReachable == false {
                consecutiveFailures = Self.failuresBeforeOffline
            } else {
                consecutiveFailures += 1
                if consecutiveFailures < Self.failuresBeforeOffline { return nil }
            }
        } else {
            consecutiveFailures = 0
        }

        if candidate == .online {
            latencyMilliseconds = probe?.latencyMilliseconds
        }
        guard candidate != verdict else { return nil }

        let change = Change(from: verdict, to: candidate)
        verdict = candidate
        lastChangedAt = date
        return change
    }
}

/// Per-target toggles, a cooldown and the Wi-Fi Monitor's quiet hours.
struct ConnectivityAlertPolicy {
    private var lastSent: [ConnectivityVerdict: Date] = [:]

    mutating func shouldNotify(
        change: ConnectivityWatchdogMachine.Change,
        settings: AppSettings.ConnectivitySettings,
        quietHours: MonitorAlertSettings,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !quietHours.isQuiet(at: now, calendar: calendar) else { return false }

        switch change.to {
        case .offline:
            guard settings.notifyOffline else { return false }
        case .captivePortal:
            guard settings.notifyCaptivePortal else { return false }
        case .online:
            // The first successful check is not a recovery.
            guard change.from != .unknown, settings.notifyRestored else { return false }
        case .unknown:
            return false
        }

        let cooldown = TimeInterval(max(0, settings.cooldownMinutes)) * 60
        if let last = lastSent[change.to], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastSent[change.to] = now
        return true
    }
}
