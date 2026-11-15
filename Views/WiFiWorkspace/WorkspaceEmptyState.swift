import AppKit
import SwiftUI

struct EmptyScanView: View {
    var hasNetworks: Bool = false
    var hasActiveFilters: Bool = false
    var onClearFilters: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "wifi.router")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.3))
            Text(hasActiveFilters ? "No matching networks" : "No networks found")
                .font(.headline)
            Text(
                hasActiveFilters
                    ? "Clear the search or filters to see all nearby networks."
                    : "Move closer to access points or refresh the scan."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if hasActiveFilters, let onClearFilters {
                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .allowsHitTesting(hasActiveFilters)
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
