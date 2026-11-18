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
    @State private var settings = AppSettingsStore.shared.settings
    @State private var settingsMessage: String?
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
                    Text("Local-only: no accounts, telemetry or cloud services.")
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
            Text(
                "Annotations, sessions, surveys, settings and crash logs stay on this Mac. LanFi has no telemetry and makes no background network calls."
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
