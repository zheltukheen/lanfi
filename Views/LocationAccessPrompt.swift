import SwiftUI

/// The app-wide explanation shown when Location Services is off.
///
/// It used to be an empty state inside the Wi-Fi analyzer, which made a
/// permission that gates several screens look like one tool's problem. It is a
/// sheet on the root window now, and the same content is reachable from the
/// banner every screen carries.
struct LocationAccessPrompt: View {
    @ObservedObject var access: LocationAccessCenter = .shared
    @Environment(\.dismiss) private var dismiss

    private var services: [(icon: String, title: LocalizedStringKey)] {
        [
            ("wifi", "Wi-Fi analyzer and scan table"),
            ("waveform.path.ecg", "Wi-Fi Monitor and its alerts"),
            ("arrow.triangle.2.circlepath", "Roaming test"),
            ("map", "Site survey and GPS points"),
            ("menubar.rectangle", "Menu bar signal"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            AppSheetHeader(
                icon: "location.circle.fill",
                title: "Location access is off",
                subtitle:
                    "macOS only reveals Wi-Fi network names (SSIDs) and access point identifiers (BSSIDs) to apps with Location Services. LanFi uses it for scanning and for GPS-tagged survey points, and nothing leaves this Mac."
            ) {
                Button("Close") { close() }
            }

            if access.state == .denied {
                Text(
                    "Access was denied in System Settings. Turn LanFi on under Privacy & Security → Location Services, then check again."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Used by")
                ForEach(services, id: \.icon) { service in
                    HStack(spacing: DesignToken.Spacing.small) {
                        Image(systemName: service.icon)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                            .frame(width: 18)
                        Text(service.title)
                            .font(.caption)
                        Spacer()
                    }
                }
            }

            Text(
                "Without it scans still run, but names and vendor identification stay hidden and monitor events are less specific."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignToken.Spacing.small) {
                AppButton("Allow Access", tone: .primary) { access.request() }
                AppButton("Open System Settings") { access.openSystemSettings() }
                AppButton("Check Again") { access.refresh() }
                Spacer()
                AppButton("Continue without", tone: .quiet) { close() }
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 380)
        .onDisappear { access.dismissPrompt() }
    }

    private func close() {
        access.dismissPrompt()
        dismiss()
    }
}

/// A one-line reminder at the top of the app shell, so the check is visible on
/// every screen rather than only where scanning happens.
struct LocationAccessBanner: View {
    @ObservedObject var access: LocationAccessCenter = .shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(.orange)
            Text("Location access is off — Wi-Fi names may stay hidden.")
                .font(.caption)
            Spacer()
            Button("Allow") { access.request() }
                .controlSize(.small)
            Button("Details") { access.presentPrompt() }
                .controlSize(.small)
        }
        .padding(.horizontal, DesignToken.Spacing.compact)
        .padding(.vertical, DesignToken.Spacing.tight)
        .background(DesignToken.Surface.warningFill)
        .overlay(
            Rectangle().frame(height: 1)
                .foregroundColor(DesignToken.Surface.tintStroke(AppPalette.warning)),
            alignment: .bottom)
    }
}
