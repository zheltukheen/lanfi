import AppKit
import LanFiCore
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar settings (D6). The screens themselves are unchanged; only the
/// navigation moved from a eleven-tab TabView to a grouped sidebar, and the
/// last section is remembered across launches.
struct SettingsView: View {
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel
    @EnvironmentObject private var analyzer: AnalyzerViewModel

    @AppStorage(AppSettingsKey.settingsSection.rawValue) private var storedSection = SettingsSection.general.rawValue

    private var selection: Binding<String> { $storedSection }

    private var section: SettingsSection {
        SettingsSection(rawValue: storedSection) ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("Application") {
                    rows([.general, .alerts, .wifi, .privacy])
                }
                Section("Analysis") {
                    rows([.vendors, .colors, .columns, .diagnostics, .hardware, .toolkit])
                }
                Section("Integrations") {
                    rows([.automation, .controllers, .mcp])
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: DesignToken.Layout.settingsSidebarMin,
                ideal: DesignToken.Layout.settingsSidebarIdeal,
                max: DesignToken.Layout.settingsSidebarMax)
        } detail: {
            detail
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            width: DesignToken.Layout.settingsWidth,
            height: DesignToken.Layout.settingsHeight
        )
        .appTableDensity()
    }

    private func rows(_ sections: [SettingsSection]) -> some View {
        ForEach(sections) { item in
            Label(item.title, systemImage: item.icon)
                .tag(item.rawValue)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general: GeneralSettingsPage()
        case .alerts: AlertSettingsView()
        case .wifi: WiFiSettingsView()
        case .vendors: VendorSettingsView()
        case .colors: ColorRulesSettingsView(viewModel: analyzer)
        case .columns: ExpressionColumnsSettingsView(viewModel: analyzer)
        case .diagnostics: DiagnosticsSettingsView()
        case .hardware: HardwareSettingsView()
        case .automation: AutomationSettingsView(viewModel: analyzer)
        case .controllers: ControllersSettingsView()
        case .mcp: MCPSettingsView()
        case .privacy: PrivacySettingsPage()
        case .toolkit: ToolkitSettingsPage()
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case alerts
    case wifi
    case vendors
    case colors
    case columns
    case diagnostics
    case hardware
    case automation
    case controllers
    case mcp
    case privacy
    case toolkit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .alerts: return String(localized: "Alerts")
        case .wifi: return String(localized: "Wi-Fi")
        case .vendors: return String(localized: "Vendors")
        case .colors: return String(localized: "Colors")
        case .columns: return String(localized: "Columns")
        case .diagnostics: return String(localized: "Diagnostics")
        case .hardware: return String(localized: "Hardware")
        case .automation: return String(localized: "Automation")
        case .controllers: return String(localized: "Controllers")
        case .mcp: return String(localized: "MCP")
        case .privacy: return String(localized: "Privacy")
        case .toolkit: return String(localized: "Toolkit")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .alerts: return "bell"
        case .wifi: return "wifi"
        case .vendors: return "building.2"
        case .colors: return "paintpalette"
        case .columns: return "tablecells"
        case .diagnostics: return "stethoscope"
        case .hardware: return "cable.connector"
        case .automation: return "clock.arrow.circlepath"
        case .controllers: return "server.rack"
        case .mcp: return "sparkles"
        case .privacy: return "hand.raised"
        case .toolkit: return "wrench.and.screwdriver"
        }
    }
}

private struct AlertSettingsView: View {
    var body: some View {
        Form {
            Section("Menu bar alerts") {
                Toggle("Weak Wi-Fi signal", isOn: binding(AppSettingsKey.alertsWeakSignal.rawValue))
                Toggle("Open networks visible", isOn: binding(AppSettingsKey.alertsOpenNetwork.rawValue))
                Toggle("Connected channel changes", isOn: binding(AppSettingsKey.alertsChannelChange.rawValue))
            }
            Section {
                Text("Weak signal alert triggers at −75 dBm for the connected network. Alerts update on each scan.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(DesignToken.Spacing.medium)
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.object(forKey: key) as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: key) }
        )
    }
}

private struct WiFiSettingsView: View {
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @AppStorage(AppSettingsKey.scanReduceInBackground.rawValue) private var reduceInBackground = true

    var body: some View {
        Form {
            Section("Wi-Fi adapter") {
                Picker(
                    "Scan interface",
                    selection: Binding(
                        get: { UserDefaults.standard.string(forKey: AppSettingsKey.wifiInterface.rawValue) ?? "" },
                        set: {
                            UserDefaults.standard.set(
                                $0.isEmpty ? nil : $0, forKey: AppSettingsKey.wifiInterface.rawValue)
                        }
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
                        get: {
                            UserDefaults.standard.object(forKey: AppSettingsKey.scanOnLaunch.rawValue) as? Bool ?? true
                        },
                        set: { UserDefaults.standard.set($0, forKey: AppSettingsKey.scanOnLaunch.rawValue) }
                    )
                )
                Toggle("Slow scans in background and Low Power Mode", isOn: $reduceInBackground)
                    .onChange(of: reduceInBackground) { _ in
                        analyzer.refreshScanCadence()
                    }
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
        .padding(DesignToken.Spacing.medium)
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
        .padding(DesignToken.Spacing.medium)
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
        .padding(DesignToken.Spacing.medium)
    }
}
