import SwiftUI
import AppKit

struct LanFiCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var uiState: AppUIState
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @ObservedObject var interfaces: InterfacesViewModel
    @ObservedObject var updater: UpdaterController

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About LanFi") {
                showAboutPanel()
            }
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }

        CommandMenu("Scan") {
            Button("Refresh Now") {
                viewModel.refresh()
            }
            .keyboardShortcut("r")

            Divider()

            Picker(
                "Scan Interval",
                selection: Binding(
                    get: { viewModel.refreshInterval },
                    set: { viewModel.updateRefreshInterval(to: $0) }
                )
            ) {
                Text("1s").tag(1.0)
                Text("3s").tag(3.0)
                Text("5s").tag(5.0)
                Text("10s").tag(10.0)
                Text("30s").tag(30.0)
            }

            Button("Custom Interval…") {
                uiState.customIntervalText = String(Int(viewModel.refreshInterval))
                uiState.showingCustomIntervalAlert = true
            }
        }

        CommandMenu("Filters") {
            Toggle("2.4 GHz", isOn: $viewModel.filterBand24)
            Toggle("5 GHz", isOn: $viewModel.filterBand5)
            Toggle("6 GHz", isOn: $viewModel.filterBand6)

            Divider()

            Picker("Min Signal", selection: $viewModel.minSignalThreshold) {
                Text("-90 dBm").tag(-90.0)
                Text("-80 dBm").tag(-80.0)
                Text("-70 dBm").tag(-70.0)
                Text("-60 dBm").tag(-60.0)
                Text("-50 dBm").tag(-50.0)
            }

            Divider()

            Button("Clear Quick Filters") {
                viewModel.clearQuickFilters()
            }

            Divider()

            Button("Search Networks…") {
                NotificationCenter.default.post(name: .wifaFocusSearch, object: nil)
            }
            .keyboardShortcut("f")
        }

        CommandMenu("Display") {
            Picker("Group By", selection: $viewModel.groupMode) {
                ForEach(NetworkGroupMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Signal Unit", selection: $viewModel.signalDisplayMode) {
                ForEach(SignalDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Highlight Connected Network", isOn: $viewModel.highlightConnectedNetworks)

            Divider()

            Menu("Column Profiles") {
                ForEach(viewModel.columnProfiles) { profile in
                    Button(profile.name) { viewModel.applyColumnProfile(profile) }
                }
                if !viewModel.columnProfiles.isEmpty { Divider() }
                Button("Save Current Profile…") { viewModel.promptSaveColumnProfile() }
                Button("Reset Columns") { viewModel.resetColumnsToDefault() }
            }
        }

        CommandMenu("Panels") {
            Toggle("Show Filters Sidebar", isOn: $uiState.showSidebar)
            Toggle("Show Inspector", isOn: $uiState.showInspector)
                .keyboardShortcut("i", modifiers: [.command, .option])

            Divider()

            Picker("Bottom Panel", selection: $uiState.selectedBottomTab) {
                Text("Insights").tag(0)
                Text("Spectrum").tag(1)
                Text("History").tag(2)
                Text("Protocols").tag(3)
                Text("Interfaces").tag(4)
                Text("Raw Data").tag(5)
                Text("Diagnostics").tag(6)
            }

            Divider()

            Button("Show Insights") { uiState.selectedBottomTab = 0 }
                .keyboardShortcut("1", modifiers: [.command])
            Button("Show Spectrum") { uiState.selectedBottomTab = 1 }
                .keyboardShortcut("2", modifiers: [.command])
            Button("Show History") { uiState.selectedBottomTab = 2 }
                .keyboardShortcut("3", modifiers: [.command])
            Button("Show Protocols") { uiState.selectedBottomTab = 3 }
                .keyboardShortcut("4", modifiers: [.command])
            Button("Show Interfaces") { uiState.selectedBottomTab = 4 }
                .keyboardShortcut("5", modifiers: [.command])
            Button("Show Raw Data") { uiState.selectedBottomTab = 5 }
                .keyboardShortcut("6", modifiers: [.command])
            Button("Show Diagnostics") { uiState.selectedBottomTab = 6 }
                .keyboardShortcut("7", modifiers: [.command])
        }

        CommandMenu("Survey") {
            Button("Open Site Survey") {
                openWindow(id: "survey")
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandMenu("Diagnostics") {
            Button("Run Network Diagnostics") {
                Task { await diagnostics.run() }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Toggle("Monitor Every 60 Seconds", isOn: $diagnostics.autoMonitor)

            Divider()

            Button("Show Diagnostics") {
                uiState.selectedBottomTab = 6
            }
            .keyboardShortcut("7", modifiers: [.command])
        }

        CommandMenu("Data") {
            Button("Save Session…") {
                viewModel.promptSaveSession()
            }

            Button("Open Session…") {
                viewModel.promptOpenSession()
            }

            if viewModel.isSessionMode {
                Button("Resume Live Scan") {
                    viewModel.resumeLiveScan()
                }
            }

            Divider()

            Button("Export CSV…") {
                viewModel.exportCSV()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Export JSON…") {
                viewModel.exportJSON()
            }

            Button("Export PCAP (Synthetic Beacons)…") {
                viewModel.exportPCAP()
            }

            Button("Export PCAPNG (Synthetic Beacons)…") {
                viewModel.exportPCAPNG()
            }

            Button("Analyze Packet Capture…") {
                NotificationCenter.default.post(name: .lanfiShowOfflineCapture, object: nil)
            }

            Divider()

            Button("Export Filter Profile…") {
                viewModel.exportFilterProfile()
            }
            Button("Import Filter Profile…") {
                viewModel.importFilterProfile()
            }

            Button("Live Capture (PCAP)…") {
                NotificationCenter.default.post(name: .lanfiShowLiveCapture, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Remote Sensors…") {
                NotificationCenter.default.post(name: .lanfiShowRemoteSensors, object: nil)
            }
        }
    }

    private func showAboutPanel() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let credits = NSAttributedString(
            string: "Native macOS Wi‑Fi Analyzer\n© 2026 LanFi Contributors\nAuthor: zheltukheen")

        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: "LanFi",
            NSApplication.AboutPanelOptionKey.applicationVersion: "Version \(version) (\(build))",
            NSApplication.AboutPanelOptionKey.credits: credits,
        ])
    }
}
