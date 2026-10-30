//  LanFiApp.swift
import SwiftUI

@main
enum LanFiMain {
    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            AppSmokeTest.run()
        }
        CrashLogger.install()
        LanFiApp.main()
    }
}

struct LanFiApp: App {
    // ViewModel создается здесь и живет все время работы приложения
    @StateObject private var viewModel = AnalyzerViewModel()
    @StateObject private var uiState = AppUIState()
    @StateObject private var diagnostics = DiagnosticsViewModel()
    @StateObject private var updater = UpdaterController()
    @StateObject private var survey = SurveyViewModel()
    @StateObject private var interfaces = InterfacesViewModel()
    @AppStorage("LanFi.highContrast") private var highContrast = false
    @AppStorage("LanFi.appearance") private var appearance = "system"

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
            MainTableView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(uiState)
                .environmentObject(diagnostics)
                .environmentObject(interfaces)
                .environment(\.lanFiHighContrast, highContrast)
                .preferredColorScheme(preferredAppearance)
                .onOpenURL { url in
                    guard let link = DeepLink.parse(url) else { return }
                    switch link {
                    case .tab(let index):
                        uiState.selectedBottomTab = index
                    case .interfaces:
                        uiState.selectedBottomTab = 2
                    case .search(let query):
                        viewModel.searchText = query
                    case .runDiagnostics:
                        uiState.selectedBottomTab = 6
                        Task { await diagnostics.run() }
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
                }
        }
        .commands {
            LanFiCommands(
                viewModel: viewModel,
                uiState: uiState,
                diagnostics: diagnostics,
                interfaces: interfaces,
                updater: updater
            )
        }

        Window("Site Survey", id: "survey") {
            SurveyView(analyzer: viewModel, survey: survey)
                .environment(\.lanFiHighContrast, highContrast)
                .preferredColorScheme(preferredAppearance)
        }

        Window("About LanFi", id: "about") {
            AboutView()
                .environment(\.lanFiHighContrast, highContrast)
                .textSelection(.enabled)
        }
        .windowResizability(.contentSize)

        WindowGroup("Tool", id: "tool", for: String.self) { $toolID in
            ToolConsoleView(toolID: toolID ?? "custom")
                .frame(minWidth: 800, minHeight: 520)
        }
        .defaultSize(width: 1000, height: 700)

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
            MenuBarView(viewModel: viewModel, diagnostics: diagnostics)
        } label: {
            Label("LanFi", systemImage: "wifi")
        }
        .menuBarExtraStyle(.window)
    }
}
