import SwiftUI

/// One screen for a fresh install: what the table shows, why macOS asks for
/// Location Services, and what LanFi never does with the data. Shown once; the
/// completion flag lives in `LanFi.hasCompletedFirstRun`.
struct FirstRunView: View {
    var onAllowLocation: () -> Void
    var onFinish: () -> Void

    private struct Point: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
    }

    private var points: [Point] {
        [
            Point(
                id: "what",
                icon: "tablecells",
                title: String(localized: "Every nearby network, decoded"),
                detail: String(
                    localized:
                        "Signal, channel and width, security, congestion and an all-band overview. Select a row for the decoded beacon details."
                )),
            Point(
                id: "location",
                icon: "location",
                title: String(localized: "Why macOS asks for Location"),
                detail: String(
                    localized:
                        "macOS only reveals network names (SSIDs) and access point identifiers (BSSIDs) to apps with Location Services. Without it LanFi still shows signal and channels, but names stay hidden."
                )),
            Point(
                id: "privacy",
                icon: "lock.shield",
                title: String(localized: "No accounts, no telemetry"),
                detail: String(
                    localized:
                        "Scanning uses public CoreWLAN APIs. Nothing leaves this Mac; annotations, sessions and surveys are stored locally."
                )),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
            HStack(spacing: DesignToken.Spacing.small) {
                Image(systemName: "wifi")
                    .font(.title2)
                    .foregroundColor(AppPalette.info)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to LanFi").font(.title2.bold())
                    Text("A native Wi-Fi analyzer for this Mac")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(points) { point in
                AppCard(padding: DesignToken.Spacing.small) {
                    HStack(alignment: .top, spacing: DesignToken.Spacing.small) {
                        Image(systemName: point.icon)
                            .font(.body)
                            .foregroundColor(AppPalette.info)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.title).font(.callout.weight(.semibold))
                            Text(point.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack(spacing: DesignToken.Spacing.small) {
                Button("Allow Location Access") {
                    onAllowLocation()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)

                Button("Start scanning") {
                    onFinish()
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("You can change this later in System Settings → Privacy & Security.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(DesignToken.Spacing.section)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
