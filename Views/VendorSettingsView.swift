import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel
    @EnvironmentObject private var analyzer: AnalyzerViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AlertSettingsView()
                .tabItem { Label("Alerts", systemImage: "bell") }
            WiFiSettingsView()
                .tabItem { Label("Wi-Fi", systemImage: "wifi") }
            VendorSettingsView()
                .tabItem { Label("Vendors", systemImage: "building.2") }
            ColorRulesSettingsView(viewModel: analyzer)
                .tabItem { Label("Colors", systemImage: "paintpalette") }
            ExpressionColumnsSettingsView(viewModel: analyzer)
                .tabItem { Label("Columns", systemImage: "tablecells") }
            DiagnosticsSettingsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            HardwareSettingsView()
                .tabItem { Label("Hardware", systemImage: "cable.connector") }
            AutomationSettingsView(viewModel: analyzer)
                .tabItem { Label("Automation", systemImage: "clock.arrow.circlepath") }
            ControllersSettingsView()
                .tabItem { Label("Controllers", systemImage: "server.rack") }
        }
        .frame(width: 620, height: 520)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var updater: UpdaterController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private func binding(_ key: String, default defaultValue: Bool = true) -> Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }

    var body: some View {
        Form {
            Section("LanFi") {
                LabeledContent("Version") { Text("\(version) (\(build))") }
                LabeledContent("Bundle") { Text(Bundle.main.bundleIdentifier ?? "-").font(.caption.monospaced()) }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            Section("Distribution") {
                Text(
                    "This build is ad-hoc signed and not notarized. On first launch, right-click LanFi.app → Open. Sparkle updates are signed independently."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Button("Open release page") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/zheltukheen/lanfi/releases/latest")!)
                }
                Button("Copy Homebrew command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        "brew tap zheltukheen/lanfi https://github.com/zheltukheen/lanfi && brew trust zheltukheen/lanfi && brew install --cask lanfi",
                        forType: .string
                    )
                }
            }

            Section("Appearance") {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "LanFi.appearance") ?? "system" },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.appearance") }
                    )
                ) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker(
                    "Table row density",
                    selection: Binding(
                        get: {
                            UserDefaults.standard.double(forKey: "LanFi.rowDensity") > 0
                                ? UserDefaults.standard.double(forKey: "LanFi.rowDensity") : 30
                        },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.rowDensity") }
                    )
                ) {
                    Text("Compact").tag(24.0)
                    Text("Standard").tag(30.0)
                    Text("Roomy").tag(38.0)
                }
            }

            Section("Toolbar") {
                Toggle("Search field", isOn: binding("LanFi.toolbar.search", default: true))
                Toggle("Export menu", isOn: binding("LanFi.toolbar.export", default: true))
                Toggle("Live capture button", isOn: binding("LanFi.toolbar.capture", default: true))
            }

            Section("Display") {
                Toggle(
                    "High contrast mode",
                    isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "LanFi.highContrast") },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.highContrast") }
                    )
                )
                .help("Increases contrast and border weight for low-vision use.")
                Toggle(
                    "Hide empty graphs",
                    isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "LanFi.hideEmptyGraphs") },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.hideEmptyGraphs") }
                    )
                )
                Toggle(
                    "Show channel recommendations",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "LanFi.graph.channel") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.graph.channel") }
                    )
                )
                Toggle(
                    "Show security audit",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "LanFi.graph.security") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.graph.security") }
                    )
                )
                Toggle(
                    "Show channel occupancy",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "LanFi.graph.occupancy") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.graph.occupancy") }
                    )
                )
            }

            Section("Data") {
                Button("Open Application Support") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("LanFi", isDirectory: true)
                    NSWorkspace.shared.open(url)
                }
                Text("Annotations, sessions, surveys, vendor overrides and crash logs stay on this Mac.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct AlertSettingsView: View {
    var body: some View {
        Form {
            Section("Menu bar alerts") {
                Toggle("Weak Wi-Fi signal", isOn: binding("LanFi.alerts.weakSignal"))
                Toggle("Open networks visible", isOn: binding("LanFi.alerts.openNetwork"))
                Toggle("Connected channel changes", isOn: binding("LanFi.alerts.channelChange"))
            }
            Section {
                Text("Weak signal alert triggers at −75 dBm for the connected network. Alerts update on each scan.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: key) as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }
}

private struct WiFiSettingsView: View {
    var body: some View {
        Form {
            Section("Wi-Fi adapter") {
                Picker(
                    "Scan interface",
                    selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "LanFi.wifiInterface") ?? "" },
                        set: { UserDefaults.standard.set($0.isEmpty ? nil : $0, forKey: "LanFi.wifiInterface") }
                    )
                ) {
                    Text("System default").tag("")
                    ForEach(WiFiInterfaceCatalog.names(), id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("External USB Wi-Fi adapters appear here when macOS exposes them through CoreWLAN.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Section("Scanning") {
                Toggle(
                    "Scan automatically on launch",
                    isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "LanFi.scanOnLaunch") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "LanFi.scanOnLaunch") }
                    )
                )
                LabeledContent("Location access") {
                    Text("Required for SSID/BSSID")
                        .foregroundColor(.secondary)
                }
                Button("Open Location Services") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct VendorSettingsView: View {
    @State private var prefix = ""
    @State private var vendor = ""
    @State private var overrides = OUIParser.customOverrides()
    @State private var isUpdating = false
    @State private var status: String?
    @State private var errorMessage: String?
    @State private var lastUpdated = OUIUpdater.lastUpdated
    @State private var autoUpdate = OUIUpdater.isAutoUpdateEnabled

    var body: some View {
        Form {
            Section("Vendor database") {
                LabeledContent("Bundled + downloaded") {
                    Text(lastUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Bundled only")
                        .foregroundColor(.secondary)
                }
                Toggle("Update automatically (weekly)", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { newValue in
                        OUIUpdater.isAutoUpdateEnabled = newValue
                    }
                HStack {
                    Button {
                        updateDatabase()
                    } label: {
                        if isUpdating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Update from Wireshark", systemImage: "arrow.down.circle")
                        }
                    }
                    .disabled(isUpdating)
                    if let status {
                        Text(status).font(.caption).foregroundColor(.secondary)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }

            Section("Custom OUI overrides") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prefix").font(.caption2).foregroundColor(.secondary)
                        TextField("", text: $prefix, prompt: Text("AA:BB:CC"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Vendor").font(.caption2).foregroundColor(.secondary)
                        TextField("", text: $vendor, prompt: Text("Acme Corp."))
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Add") {
                        guard OUIParser.setOverride(prefix: prefix, vendor: vendor) else {
                            errorMessage = "Prefix must be 6–9 hex characters and vendor must not be empty."
                            return
                        }
                        overrides = OUIParser.customOverrides()
                        prefix = ""
                        vendor = ""
                        errorMessage = nil
                    }
                }
                Text("6–9 hex digits, e.g. 001122 or 00:11:22. Overrides apply after the next scan.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach(overrides.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack {
                        Text(key).font(.system(.caption, design: .monospaced))
                        Text(value).font(.caption)
                        Spacer()
                        Button(role: .destructive) {
                            OUIParser.removeOverride(key)
                            overrides = OUIParser.customOverrides()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove OUI override")
                    }
                }
            }

            Section {
                Text("Overrides are stored locally and win over the downloaded database.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { overrides = OUIParser.customOverrides() }
    }

    private func updateDatabase() {
        isUpdating = true
        errorMessage = nil
        status = nil
        Task {
            do {
                let date = try await OUIUpdater.update()
                await MainActor.run {
                    isUpdating = false
                    lastUpdated = date
                    status = "Updated"
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel

    var body: some View {
        Form {
            Section("Diagnostics") {
                if let report = diagnostics.report {
                    LabeledContent("Last run") {
                        Text(report.startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Health") { Text("\(report.healthScore)/100") }
                } else {
                    Text("No diagnostics report yet.").foregroundColor(.secondary)
                }
                Button("Export Diagnostics Bundle…") {
                    DiagnosticsBundleExporter.exportWithPanel(
                        report: diagnostics.report,
                        history: diagnostics.history,
                        interfaces: nil
                    )
                }
                Button("Clear Diagnostics History") {
                    diagnostics.clearHistory()
                }
                .disabled(diagnostics.history.isEmpty)
            }

            Section("Crash logs") {
                Button("Open Crash Logs Folder") {
                    NSWorkspace.shared.open(CrashLogger.logDirectoryURL())
                }
                Text("Crash logs are local-only and included in the diagnostics bundle. LanFi has no telemetry.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
