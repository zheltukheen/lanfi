import AppKit
import LanFiCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings → General, rebuilt on the shared card and spacing tokens. Every
/// toggle writes through `AppSettingsStore`, whose legacy mirrors are the keys
/// the app already observes, so changes apply immediately.
struct GeneralSettingsPage: View {
    @EnvironmentObject private var updater: UpdaterController
    @Environment(\.openWindow) private var openWindow

    @StateObject private var launchAtLogin = LaunchAtLoginController()
    @StateObject private var linkAutomation = LinkAutomation.shared
    @State private var settings = AppSettingsStore.shared.settings
    @State private var settingsMessage: String?
    /// Set when the notification prompt is refused, so the automation card can
    /// say why the Wi-Fi switches would be silent instead of just doing nothing.
    @State private var notificationDenied = false
    @AppStorage(AccessibilityPalette.colorBlindSafeKey) private var colorBlindSafe = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                aboutCard
                appearanceCard
                startupCard
                updatesCard
                menuBarCard
                connectivityCard
                linkAutomationCard
                displayCard
                dataCard
                helpCard
            }
            .padding(DesignToken.Spacing.large)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLogin.refresh()
            settings = AppSettingsStore.shared.settings
        }
    }

    // MARK: - Cards

    private var aboutCard: some View {
        AppCard {
            HStack(spacing: DesignToken.Spacing.medium) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
                    Text("LanFi").font(.title3.bold())
                    Text("Wi-Fi analyzer and network toolkit · \(version) (\(build))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("No accounts, no cloud services. Anonymous statistics are optional and off by default.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                StatusPill(
                    text: launchAtLogin.isEnabled
                        ? String(localized: "Starts at login")
                        : String(localized: "Manual launch"),
                    tone: launchAtLogin.isEnabled ? .good : .neutral)
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard(title: "Appearance", icon: "paintbrush") {
            LabeledContent("Theme") {
                Picker("Theme", selection: binding(\.appearance)) {
                    Text("System").tag(AppSettings.Appearance.system)
                    Text("Light").tag(AppSettings.Appearance.light)
                    Text("Dark").tag(AppSettings.Appearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: DesignToken.Layout.controlWidthLarge)
            }
            LabeledContent("Table rows") {
                Picker("Table rows", selection: binding(\.rowDensity)) {
                    ForEach(TableDensity.allCases) { density in
                        Text(density.title).tag(density.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: DesignToken.Layout.controlWidthLarge)
            }
            Toggle("High contrast mode", isOn: binding(\.highContrast))
                .help("Increases contrast and border weight for low-vision use.")
            Toggle("Colour-blind friendly palette", isOn: colorBlindSafeBinding)
                .help("Uses blue, amber and magenta instead of red and green for status and quality.")
            HStack(spacing: DesignToken.Spacing.medium) {
                Text("Palette preview").font(.caption).foregroundColor(.secondary)
                swatch("Good", AppPalette.quality(85))
                swatch("Fair", AppPalette.quality(55))
                swatch("Poor", AppPalette.quality(20))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Palette preview: good, fair, poor")
            Text("Row density applies to every table and list immediately.")
                .settingsHint()
        }
    }

    private func swatch(_ title: String, _ color: Color) -> some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.caption2)
        }
    }

    private var startupCard: some View {
        SettingsCard(title: "Startup", icon: "power") {
            Toggle(
                "Launch LanFi at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }))
            Text(launchAtLogin.statusDescription).settingsHint()
            if let error = launchAtLogin.errorMessage {
                Text(error).font(.caption2).foregroundColor(AppPalette.danger)
            }
            Toggle("Start scanning on launch", isOn: binding(\.scanOnLaunch))
            LabeledContent("Refresh interval") {
                Picker("Refresh interval", selection: binding(\.refreshInterval)) {
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("3 s").tag(3.0)
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private var updatesCard: some View {
        SettingsCard(title: "Updates", icon: "arrow.triangle.2.circlepath") {
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }))
            HStack(spacing: DesignToken.Spacing.small) {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                if let date = updater.lastUpdateCheckDate {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .settingsHint()
                } else {
                    Text("No update check yet").settingsHint()
                }
            }
            Text(
                "Updates are signed with Sparkle and delivered from GitHub Releases. This build is ad-hoc signed, so on first launch use right-click → Open."
            )
            .settingsHint()
            HStack(spacing: DesignToken.Spacing.small) {
                Button("Release Notes") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/zheltukheen/lanfi/releases/latest")!)
                }
                Button("Copy Homebrew Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "brew tap zheltukheen/lanfi https://github.com/zheltukheen/lanfi && brew trust zheltukheen/lanfi && brew install --cask lanfi",
                        forType: .string)
                }
            }
        }
    }

    private var menuBarCard: some View {
        SettingsCard(title: "Menu bar", icon: "menubar.rectangle") {
            Picker("Label", selection: menuBarBinding(\.labelStyle)) {
                Text("Icon only").tag(AppSettings.MenuBarMeterSettings.LabelStyle.iconOnly)
                Text("Icon + number").tag(AppSettings.MenuBarMeterSettings.LabelStyle.iconAndNumber)
                Text("Icon + graph").tag(AppSettings.MenuBarMeterSettings.LabelStyle.iconAndGraph)
                Text("Icon + graph + number").tag(
                    AppSettings.MenuBarMeterSettings.LabelStyle.iconGraphAndNumber)
            }
            Picker("Metric", selection: menuBarBinding(\.metric)) {
                Text("Throughput").tag(AppSettings.MenuBarMeterSettings.Metric.throughput)
                Text("Signal").tag(AppSettings.MenuBarMeterSettings.Metric.signal)
                Text("Quality").tag(AppSettings.MenuBarMeterSettings.Metric.quality)
                Text("Latency").tag(AppSettings.MenuBarMeterSettings.Metric.latency)
            }
            Picker("Throughput unit", selection: menuBarBinding(\.unit)) {
                Text("bit/s").tag(AppSettings.MenuBarMeterSettings.Unit.bits)
                Text("byte/s").tag(AppSettings.MenuBarMeterSettings.Unit.bytes)
            }
            Text("Counters are sampled every 2 s, and every 30 s while LanFi is in the background.")
                .settingsHint()
        }
    }

    private var connectivityCard: some View {
        SettingsCard(title: "Connectivity watchdog", icon: "network") {
            Toggle("Watch connectivity", isOn: connectivityBinding(\.enabled))
                .help("Checks the internet every few seconds and flips the menu-bar state when it drops.")
            LabeledContent("Check every") {
                Picker("Check every", selection: connectivityBinding(\.intervalSeconds)) {
                    Text("15 s").tag(15.0)
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
                .labelsHidden()
                .frame(width: 110)
            }
            LabeledContent("Primary probe") {
                TextField("URL", text: connectivityBinding(\.primaryProbeURL))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Fallback probe") {
                TextField("URL", text: connectivityBinding(\.fallbackProbeURL))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }
            Toggle("Notify when offline", isOn: connectivityBinding(\.notifyOffline))
            Toggle("Notify on a captive portal", isOn: connectivityBinding(\.notifyCaptivePortal))
            Toggle("Notify when the connection returns", isOn: connectivityBinding(\.notifyRestored))
            Text(
                "A single failed probe never flips the state, and quiet hours come from the Wi-Fi Monitor alerts. Probes are plain HTTP GETs to the captive-portal endpoints; nothing is uploaded."
            )
            .settingsHint()
        }
    }

    private var linkAutomationCard: some View {
        SettingsCard(title: "Ethernet and Wi-Fi", icon: "cable.connector") {
            Toggle(
                "Turn Wi-Fi off while Ethernet is connected",
                isOn: linkAutomationBinding)
            Text(
                "Turning this on asks macOS for notification permission: each switch is announced as a banner, and without permission it would change silently. Writes the Wi-Fi power state with networksetup: when a physical Ethernet link comes up LanFi turns Wi-Fi off once, and when the cable goes away it turns Wi-Fi back on once. A manual Wi-Fi change always wins: if you switch Wi-Fi back on while docked, LanFi leaves it alone. Off by default."
            )
            .settingsHint()
            if notificationDenied && settings.automation.linkAutomation {
                HStack(alignment: .firstTextBaseline, spacing: DesignToken.Spacing.small) {
                    Text("Notifications are off for LanFi, so the Wi-Fi switches stay silent.")
                        .font(.caption2)
                        .foregroundColor(AppPalette.warning)
                    Spacer()
                    Button("Open Notification Settings…") { openNotificationSettings() }
                        .controlSize(.small)
                }
            }
            if linkAutomation.isEnabled {
                Toggle("Pause automation", isOn: $linkAutomation.isPaused)
                LabeledContent("Ethernet") {
                    Text(linkAutomation.wiredInterface ?? String(localized: "Not connected"))
                        .font(.caption.monospaced())
                        .foregroundColor(linkAutomation.wiredConnected ? AppPalette.ok : .secondary)
                }
                LabeledContent("Wi-Fi") {
                    Text(wifiStateLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let action = linkAutomation.lastAction, let at = linkAutomation.lastActionAt {
                    Text(
                        verbatim:
                            "\(action.detail) \(at.formatted(date: .omitted, time: .shortened))"
                    )
                    .settingsHint()
                }
                if let error = linkAutomation.lastError {
                    Text(error).font(.caption2).foregroundColor(AppPalette.danger)
                }
            }
        }
    }

    private var wifiStateLabel: String {
        switch linkAutomation.wifiPowerOn {
        case true?: return String(localized: "On")
        case false?: return String(localized: "Off")
        case nil: return String(localized: "Unknown")
        }
    }

    private var displayCard: some View {
        SettingsCard(title: "Display", icon: "rectangle.3.group") {
            Toggle("Hide empty graphs", isOn: binding(\.hideEmptyGraphs))
            Toggle("Show channel recommendations", isOn: binding(\.showChannelRecommendations))
            Toggle("Show security audit", isOn: binding(\.showSecurityAudit))
            Toggle("Show channel occupancy", isOn: binding(\.showChannelOccupancy))
            Divider()
            Toggle("Search field in toolbar", isOn: binding(\.toolbarSearch))
            Toggle("Export menu in toolbar", isOn: binding(\.toolbarExport))
        }
    }

    private var dataCard: some View {
        SettingsCard(title: "Data & privacy", icon: "externaldrive") {
            HStack(spacing: DesignToken.Spacing.small) {
                Button("Export Settings…") { exportSettings() }
                Button("Import Settings…") { importSettings() }
                Button("Open Application Support") {
                    let url = FileManager.default.urls(
                        for: .applicationSupportDirectory, in: .userDomainMask
                    )[0].appendingPathComponent("LanFi", isDirectory: true)
                    NSWorkspace.shared.open(url)
                }
            }
            if let settingsMessage {
                Text(settingsMessage).settingsHint()
            }
            Toggle("Watch gateway and DNS integrity", isOn: binding(\.automation.gatewayGuard))
            Text(
                "Re-reads the default gateway's MAC from the ARP table every 2 minutes and compares a canary DNS lookup with Cloudflare every 10 minutes. Only that lookup leaves the Mac; findings stay local."
            )
            .settingsHint()
            Toggle("Watch VPN state and leaks", isOn: binding(\.automation.vpnGuard))
            Text(
                "Shows whether a tunnel is up and flags a resolver or IPv6 default route that looks like it bypasses it. Local reads only: no provider API and no credentials."
            )
            .settingsHint()
            if ServiceDescriptionResolver.isModelAvailable {
                Toggle(
                    "Describe unknown services with the on-device model",
                    isOn: binding(\.automation.serviceDescriptions))
                Text(
                    "Known services use the bundled offline map. The on-device model only labels unknown names, runs locally and never uploads anything."
                )
                .settingsHint()
            }
            Text(
                "Annotations, sessions, surveys, settings and crash logs stay on this Mac. LanFi has no telemetry; the only background request is the connectivity watchdog's captive-portal probe, which you can turn off above."
            )
            .settingsHint()
        }
    }

    private var helpCard: some View {
        SettingsCard(title: "Help & support", icon: "questionmark.circle") {
            HStack(spacing: DesignToken.Spacing.small) {
                Button("Open LanFi Help") { openWindow(id: "help") }
                    .keyboardShortcut("?", modifiers: [.command])
                Button("Open Crash Logs") {
                    NSWorkspace.shared.open(CrashLogger.logDirectoryURL())
                }
            }
            Text(
                "The help window covers the toolkit, LAN Scanner, Device Shelf, surveys, MCP and keyboard shortcuts."
            )
            .settingsHint()
        }
    }

    // MARK: - Bindings and files

    private func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                settings[keyPath: keyPath] = newValue
                AppSettingsStore.shared.save(settings)
            }
        )
    }

    /// Turning the automation on is the only moment LanFi may ask for
    /// notification permission: the feature's whole output is a banner, and
    /// `UNUserNotificationCenter` silently drops posts until it is granted.
    ///
    /// The permission is requested only when the switch goes off → on, never on
    /// every view appearance, and the request result drives the inline warning.
    private var linkAutomationBinding: Binding<Bool> {
        Binding(
            get: { settings.automation.linkAutomation },
            set: { newValue in
                let wasOn = settings.automation.linkAutomation
                settings.automation.linkAutomation = newValue
                AppSettingsStore.shared.save(settings)
                guard newValue, !wasOn else { return }
                Task { @MainActor in
                    let granted = await MonitorNotifier.shared.requestAuthorization()
                    notificationDenied = !granted
                    if granted { await LinkAutomation.shared.sampleNow() }
                }
            }
        )
    }

    private func openNotificationSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.notifications")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Resolve the palette cache before the defaults change, so the redraw that
    /// follows the toggle reads the new hues instead of the previous ones.
    private var colorBlindSafeBinding: Binding<Bool> {
        Binding(
            get: { colorBlindSafe },
            set: { enabled in
                AccessibilityPalette.setEnabled(enabled)
                colorBlindSafe = enabled
            })
    }

    private func menuBarBinding<T>(
        _ keyPath: WritableKeyPath<AppSettings.MenuBarMeterSettings, T>
    ) -> Binding<T> {
        Binding(
            get: { settings.menuBar[keyPath: keyPath] },
            set: { newValue in
                var updated = settings
                updated.menuBar[keyPath: keyPath] = newValue
                settings = updated
                AppSettingsStore.shared.save(updated)
            }
        )
    }

    private func connectivityBinding<T>(
        _ keyPath: WritableKeyPath<AppSettings.ConnectivitySettings, T>
    ) -> Binding<T> {
        Binding(
            get: { settings.connectivity[keyPath: keyPath] },
            set: { newValue in
                var updated = settings
                updated.connectivity[keyPath: keyPath] = newValue
                settings = updated
                AppSettingsStore.shared.save(updated)
            }
        )
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "LanFi-settings.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AppSettingsStore.shared.export(to: url)
            settingsMessage = String(localized: "Settings exported.")
        } catch {
            settingsMessage = String(
                format: String(localized: "Export failed: %@"), error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try AppSettingsStore.shared.importSettings(from: url)
            settings = AppSettingsStore.shared.settings
            settingsMessage = String(localized: "Settings imported.")
        } catch {
            settingsMessage = String(
                format: String(localized: "Import failed: %@"), error.localizedDescription)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                HStack(spacing: DesignToken.Spacing.small) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundColor(.secondary)
                }
                content
            }
        }
    }
}

private extension View {
    func settingsHint() -> some View {
        font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

}
