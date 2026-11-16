import AppKit
import SwiftUI

/// Every "nothing to show" case in one place: no scan yet, no networks, no
/// permission, no Wi-Fi hardware, failed scan, stale data and over-filtering.
/// Each state names the cause and offers the action that fixes it.
struct EmptyScanView: View {
    let placeholder: WorkspacePlaceholder
    var onRefresh: () -> Void = {}
    var onAllowLocation: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onClearFilters: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.3))
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if case .noNetworks = placeholder {
                Text(VisibilityAdvisor.emptyScanHint)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }

            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var icon: String {
        switch placeholder {
        case .filtered: return "line.3.horizontal.decrease.circle"
        case .noPermission: return "location.slash"
        case .noWiFiHardware: return "wifi.slash"
        case .scanFailed: return "exclamationmark.triangle"
        case .staleData: return "clock.badge.exclamationmark"
        case .noScan, .noNetworks: return "wifi.router"
        case .none: return "wifi.router"
        }
    }

    private var title: String {
        switch placeholder {
        case .filtered: return String(localized: "No matching networks")
        case .noPermission: return String(localized: "Location access is off")
        case .noWiFiHardware: return String(localized: "No Wi-Fi hardware")
        case .scanFailed: return String(localized: "Scan failed")
        case .staleData: return String(localized: "The scan stopped updating")
        case .noScan: return String(localized: "No scan yet")
        case .noNetworks: return String(localized: "No networks found")
        case .none: return ""
        }
    }

    private var message: String {
        switch placeholder {
        case .filtered:
            return String(localized: "Clear the search or filters to see all nearby networks.")
        case .noPermission:
            return String(
                localized:
                    "macOS hides SSIDs and BSSIDs from apps without Location Services. Other scan data still works."
            )
        case .noWiFiHardware:
            return String(
                localized:
                    "macOS did not report a Wi-Fi interface. Check that this Mac has Wi-Fi and that the radio is on."
            )
        case .scanFailed(let detail):
            return detail
        case .staleData:
            return String(
                localized:
                    "The newest scan is older than expected, so the table may not match what is in the air right now."
            )
        case .noScan:
            return String(
                localized:
                    "LanFi scans automatically every few seconds. Refresh now if you expected results already."
            )
        case .noNetworks:
            return String(
                localized: "Move closer to an access point and refresh the scan.")
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch placeholder {
        case .filtered:
            Button("Clear Filters", action: onClearFilters)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .noPermission:
            HStack(spacing: 8) {
                Button("Allow Access", action: onAllowLocation)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Open System Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .noScan, .noNetworks, .scanFailed, .noWiFiHardware, .staleData:
            HStack(spacing: 8) {
                Button("Refresh Now", action: onRefresh)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                if case .noWiFiHardware = placeholder {
                    Button("Open System Settings", action: onOpenSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        case .none:
            EmptyView()
        }
    }
}

/// Shown above a populated table when scans stopped arriving.
struct StaleDataBanner: View {
    let lastScan: Date?
    var onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundColor(AppPalette.warning)
            Text(
                lastScan.map {
                    "Showing data from \($0.formatted(date: .omitted, time: .shortened)); the scan may have stalled."
                } ?? "The scan may have stalled."
            )
            .font(.caption)
            Spacer()
            Button("Refresh Now", action: onRefresh)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppPalette.warning.opacity(0.1))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(AppPalette.warning.opacity(0.2)),
            alignment: .bottom)
    }
}

struct CompactPermissionBanner: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(.orange)
            Text("Location access is off — SSID/BSSID may be hidden. Other scan data still works.")
                .font(.caption)
            Spacer()
            Button("Allow") {
                viewModel.requestLocationAuthorization()
            }
            .controlSize(.small)
            Button("Settings") {
                viewModel.openSystemLocationSettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.2)), alignment: .bottom)
    }
}

struct ScanHealthBanner: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    let health: ScanHealth

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(health.title).font(.caption.bold())
                Text(health.message).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button("Open Settings") {
                viewModel.openSystemLocationSettings()
            }
            .controlSize(.small)
            Button("Check Again") {
                viewModel.checkLocationAuthorization()
            }
            .controlSize(.small)
            Button {
                viewModel.dismissScanHealth()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.red.opacity(0.2)), alignment: .bottom)
    }
}

struct LocationPermissionView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Location access is required")
                .font(.title3.bold())
            Text(
                "macOS only reveals Wi-Fi network names (SSIDs) and access point identifiers (BSSIDs) to apps with Location Services enabled. LanFi uses this permission solely for scanning and never stores or transmits your location."
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)

            HStack(spacing: 10) {
                Button("Allow Access") {
                    viewModel.requestLocationAuthorization()
                }
                .buttonStyle(.borderedProminent)

                Button("Open System Settings") {
                    viewModel.openSystemLocationSettings()
                }
                .buttonStyle(.bordered)

                Button("Check Again") {
                    viewModel.checkLocationAuthorization()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
