import LanFiCore
import SwiftUI

/// Settings → Privacy. LanFi is a local tool, so this page is mostly about
/// saying exactly what leaves the Mac (nothing by default) and what could be
/// sent when the user opts in to anonymous statistics.
struct PrivacySettingsPage: View {
    @AppStorage(AppSettingsKey.anonymousStatistics.rawValue)
    private var anonymousStatistics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                summaryCard
                statisticsCard
                boundariesCard
                rightsCard
            }
            .padding(DesignToken.Spacing.large)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var summaryCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("Privacy policy")
                    .font(.title3.bold())
                Text(
                    "LanFi runs on your Mac. It has no account, no cloud sync and no advertising SDK. Measurement data — networks, devices, captures, survey samples and traffic counters — stays in the app's own container until you delete it."
                )
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text("Last updated: 19 November 2026")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statisticsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Toggle("Allow anonymous usage statistics", isOn: $anonymousStatistics)
                    .font(.callout.weight(.medium))
                Text(
                    "Off by default. When enabled, LanFi may send anonymised counters — app version, macOS version, which tools were opened and how often, and whether a run succeeded — to improve the app. These records carry no SSID, BSSID, IP address, host name, domain, device name, file path or free-text field, and they are never linked to a person or an account."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Current build: nothing is transmitted yet. The switch records your choice so a future build can honour it; no statistics leave this Mac today."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if !anonymousStatistics {
                    Text("Anonymous statistics are disabled.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var boundariesCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("What LanFi never collects")
                    .font(.headline)
                policyRow(
                    "wifi.slash", "Network names, BSSIDs, channels and signal readings")
                policyRow(
                    "number", "IP and MAC addresses, host names and device names")
                policyRow(
                    "magnifyingglass", "Domains, URLs, DNS queries and captured traffic")
                policyRow(
                    "map", "Survey floor plans, samples and photos you import")
                policyRow(
                    "person.crop.circle", "Accounts, contacts and any personal identifier")
            }
        }
    }

    private var rightsCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                Text("Your data, your files")
                    .font(.headline)
                Text(
                    "Everything LanFi stores lives in its Application Support folder and can be exported or removed from Settings → General → Data. Uninstalling the app and deleting that folder removes all of it; with anonymous statistics off, nothing needs to be requested from us."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Link(
                    "Read the full policy on GitHub",
                    destination: URL(string: "https://github.com/zheltukheen/lanfi/blob/main/PRIVACY.md")!
                )
                .font(.caption)
            }
        }
    }

    private func policyRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
