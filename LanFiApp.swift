//  LanFiApp.swift
import SwiftUI

@main
enum LanFiMain {
    static func main() {
        // Headless MCP mode: `LanFi.app/Contents/MacOS/LanFi --mcp` speaks the
        // protocol on stdio and never starts AppKit, so an MCP client can point
        // at the installed app instead of a separate CLI binary.
        if CommandLine.arguments.contains("--mcp") {
            MCPServer.run()
        }
        if CommandLine.arguments.contains("--smoke-test") {
            AppSmokeTest.run()
        }
        CrashLogger.install()
        LanFiApp.main()
    }
}

struct LanFiApp: App {
    init() {
        Task.detached(priority: .utility) {
            OUIParser.preload()
        }
    }

    // ViewModel создается здесь и живет все время работы приложения
    @StateObject private var viewModel = AnalyzerViewModel()
    @StateObject private var uiState = AppUIState()
    @StateObject private var diagnostics = DiagnosticsViewModel()
    @StateObject private var updater = UpdaterController()
    @StateObject private var survey = SurveyViewModel()
    @StateObject private var interfaces = InterfacesViewModel()
    @StateObject private var toolkit = ToolkitViewModel()
    @StateObject private var uptime = UptimeMonitor()
    @StateObject private var meter = MenuBarMeterModel()
    @StateObject private var connectivity = ConnectivityWatchdog.shared
    @AppStorage("LanFi.highContrast") private var highContrast = false
    @AppStorage(AccessibilityPalette.colorBlindSafeKey) private var colorBlindSafe = false
    @AppStorage("LanFi.appearance") private var appearance = "system"
    @AppStorage("LanFi.hasCompletedFirstRun") private var hasCompletedFirstRun = false

    private var preferredAppearance: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // Свойство для отслеживания состояния приложения (активно/фон)
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            NetworkToolkitView(toolkit: toolkit)
                // `AppPalette` resolves colours from a cached flag, so flipping
                // the palette changes nothing a view can observe. Rebuilding
                // this subtree is the one guaranteed way to repaint every
                // leaf without restarting; view models and stored settings
                // live outside the identity and survive.
                .id(colorBlindSafe)
                .frame(minWidth: 1000, minHeight: 640)
                .environmentObject(viewModel)
                .environmentObject(uiState)
                .environmentObject(diagnostics)
                .environmentObject(interfaces)
                .environmentObject(survey)
                .environmentObject(uptime)
                .environmentObject(toolkit)
                .environment(\.lanFiHighContrast, highContrast)
                .preferredColorScheme(preferredAppearance)
                .onAppear {
                    meter.start()
                    connectivity.start()
                    GatewayGuard.shared.start()
                    VPNGuard.shared.start()
                    LinkAutomation.shared.start()
                    TrafficAccounting.shared.start()
                    AppTrafficHistoryModel.shared.start()
                }
                .sheet(
                    isPresented: Binding(
                        get: { !hasCompletedFirstRun },
                        set: { presented in
                            if !presented { hasCompletedFirstRun = true }
                        })
                ) {
                    FirstRunView(
                        onAllowLocation: { viewModel.requestLocationAuthorization() },
                        onFinish: { hasCompletedFirstRun = true })
                }
                .onOpenURL { url in
                    guard let link = DeepLink.parse(url) else { return }
                    switch link {
                    case .tab(let index):
                        if index == 2 {
                            toolkit.select(.networkMonitor)
                        } else if index == 6 {
                            toolkit.select(.internetCheck)
                        } else {
                            toolkit.select(.wifiAnalyzer)
                            uiState.selectedBottomTab = index
                        }
                    case .interfaces:
                        toolkit.select(.networkMonitor)
                    case .search(let query):
                        toolkit.select(.wifiAnalyzer)
                        viewModel.searchText = query
                    case .runDiagnostics:
                        toolkit.select(.internetCheck)
                        Task { await diagnostics.run() }
                    case .toolkit(let tool):
                        toolkit.select(tool)
                    case .device(let tag):
                        // The scanner screen may not be on screen yet, so keep
                        // the tag until the shelf is ready to consume it.
                        toolkit.select(.lanScanner)
                        DeviceShelfLink.pendingTag = tag
                        NotificationCenter.default.post(
                            name: .lanfiSelectShelfDevice, object: nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        // ИСПРАВЛЕНО: Вызываем публичный метод ViewModel
                        viewModel.checkLocationAuthorization()

                        // Если права уже есть, запускаем сканирование
                        if viewModel.isLocationAuthorized {
                            viewModel.refresh()
                        }

                        // Opt-in weekly vendor database refresh; no-ops unless enabled and stale.
                        Task { await OUIUpdater.runScheduledUpdateIfNeeded() }
                    }
                    meter.setApplicationActive(newPhase == .active)
                    connectivity.setApplicationActive(newPhase == .active)
                }
        }
        .commands {
            LanFiCommands(
                viewModel: viewModel,
                uiState: uiState,
                updater: updater,
                diagnostics: diagnostics,
                survey: survey
            )
        }

        Window("About LanFi", id: "about") {
            AboutView()
                .environment(\.lanFiHighContrast, highContrast)
                .textSelection(.enabled)
        }
        .windowResizability(.contentSize)

        Window("Spectrum", id: "spectrum") {
            SpectrumView(viewModel: viewModel, isFullScreen: true)
                .frame(minWidth: 1100, minHeight: 650)
        }

        Window("History", id: "history") {
            SignalHistoryView(viewModel: viewModel, isFullScreen: true)
                .frame(minWidth: 1100, minHeight: 650)
        }

        Window("LanFi Help", id: "help") {
            HelpView()
                .environment(\.lanFiHighContrast, highContrast)
                .textSelection(.enabled)
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
                .environmentObject(updater)
                .environmentObject(diagnostics)
                .environmentObject(viewModel)
                .environment(\.lanFiHighContrast, highContrast)
                .preferredColorScheme(preferredAppearance)
        }

        MenuBarExtra {
            MenuBarView(
                viewModel: viewModel, diagnostics: diagnostics, uptime: uptime, meter: meter,
                connectivity: connectivity
            )
            .environmentObject(uiState)
            .environmentObject(toolkit)
        } label: {
            MenuBarLabel(
                meter: meter, viewModel: viewModel, diagnostics: diagnostics, uptime: uptime,
                connectivity: connectivity)
        }
        .menuBarExtraStyle(.window)
    }
}
