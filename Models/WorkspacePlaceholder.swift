import Foundation

/// What the Wi-Fi workspace should say instead of an empty table.
///
/// The decision is pure so the whole matrix (no scan, no permission, no
/// hardware, failed scan, stale data, filters) can be tested without CoreWLAN
/// or SwiftUI.
enum WorkspacePlaceholder: Equatable {
    case none
    /// Nothing has been scanned yet.
    case noScan
    /// A scan completed and reported no nearby networks.
    case noNetworks
    case noPermission
    case noWiFiHardware
    case scanFailed(String)
    /// Rows exist but the newest scan is older than expected.
    case staleData(Date?)
    /// Networks exist but the current filters hide all of them.
    case filtered
}

enum WorkspacePlaceholderEvaluator {
    /// A scan interval of 3 s is considered stale after 45 s; slower user
    /// intervals stretch the window so a deliberate 30 s cadence is not flagged.
    static func staleAfter(_ scanInterval: TimeInterval) -> TimeInterval {
        max(45, scanInterval * 10)
    }

    static func evaluate(
        scanHealth: ScanHealth,
        visibleCount: Int,
        totalCount: Int,
        hasActiveFilters: Bool,
        lastScan: Date?,
        isSessionLoaded: Bool,
        scanInterval: TimeInterval,
        now: Date = Date()
    ) -> WorkspacePlaceholder {
        if totalCount > 0 && visibleCount == 0 && hasActiveFilters {
            return .filtered
        }

        if case .scanFailed(let detail) = scanHealth {
            return .scanFailed(detail)
        }

        switch scanHealth {
        case .noWiFiHardware:
            return .noWiFiHardware
        case .permissionDenied:
            return .noPermission
        default:
            break
        }

        let isStale: Bool
        if let lastScan, !isSessionLoaded {
            isStale = now.timeIntervalSince(lastScan) > staleAfter(scanInterval)
        } else {
            isStale = false
        }

        if visibleCount == 0 && totalCount == 0 {
            return isStale ? .staleData(lastScan) : .noScan
        }
        if isStale {
            return .staleData(lastScan)
        }
        return .none
    }
}
