import Foundation

/// Why a scan produced no usable rows.
///
/// Since macOS 14.4 CoreWLAN returns networks with an empty SSID and BSSID when
/// it cannot verify the app's code signature against the Location Services
/// grant. Scan calls still succeed, so the table would silently show a list of
/// unnamed rows. This value drives an explicit, fixable diagnostic instead.
enum ScanHealth: Equatable {
    /// Scanning works and identifiers are visible.
    case healthy
    /// The scan itself failed (Wi-Fi off, no interface, driver error).
    case scanFailed(String)
    /// No networks were returned while Location Services is authorized.
    case noNetworks
    /// Location Services is not authorized, so scanning may be limited.
    case permissionDenied
    /// Rows came back, but every SSID and BSSID was withheld by macOS.
    case identifiersHidden
    /// macOS reports no Wi-Fi interface at all (no radio, or the driver is not
    /// attached).
    case noWiFiHardware

    /// Whether the workspace should show its own banner for this state.
    var requiresBanner: Bool {
        switch self {
        case .identifiersHidden: return true
        case .healthy, .scanFailed, .noNetworks, .permissionDenied, .noWiFiHardware: return false
        }
    }

    var title: String {
        switch self {
        case .healthy: return ""
        case .scanFailed: return "Scan failed"
        case .noNetworks: return "No networks found"
        case .permissionDenied: return "Location access is off"
        case .identifiersHidden: return "Network names are hidden"
        case .noWiFiHardware: return "No Wi-Fi hardware"
        }
    }

    var message: String {
        switch self {
        case .healthy:
            return ""
        case .scanFailed(let detail):
            return detail
        case .noNetworks:
            return "Nearby access points were not reported. Move closer to an access point and refresh."
        case .permissionDenied:
            return "macOS hides SSIDs and BSSIDs from apps without Location Services. Other scan data still works."
        case .identifiersHidden:
            return
                "macOS withheld every SSID and BSSID. That usually means Location Services no longer trusts this build's signature — common for ad-hoc signed builds after an update. Re-grant Location access, or install a signed build."
        case .noWiFiHardware:
            return
                "macOS did not report a Wi-Fi interface. Check that this Mac has Wi-Fi and that the radio is powered on, then refresh."
        }
    }
}

enum ScanHealthEvaluator {
    /// Pure decision so the matrix is testable without CoreWLAN.
    static func evaluate(
        networks: [NetworkModel],
        errorMessage: String?,
        isLocationAuthorized: Bool,
        hasWiFiInterface: Bool = true
    ) -> ScanHealth {
        guard hasWiFiInterface else { return .noWiFiHardware }
        if let errorMessage, !errorMessage.isEmpty {
            return .scanFailed(errorMessage)
        }
        guard !networks.isEmpty else {
            return isLocationAuthorized ? .noNetworks : .permissionDenied
        }
        let allNamesHidden = networks.allSatisfy { $0.ssid.isEmpty }
        let allIdentifiersHidden = networks.allSatisfy { $0.bssid.isEmpty }
        if allNamesHidden && allIdentifiersHidden {
            return .identifiersHidden
        }
        return .healthy
    }
}
