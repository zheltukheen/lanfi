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
    @AppStorage("Wifa.highContrast") private var highContrast = false

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
        }

        Window("About LanFi", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("LanFi Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 900, height: 620)

        Settings {
            SettingsView()
                .environmentObject(updater)
                .environmentObject(diagnostics)
                .environmentObject(viewModel)
                .environment(\.lanFiHighContrast, highContrast)
        }

        MenuBarExtra {
            MenuBarView(viewModel: viewModel, diagnostics: diagnostics)
        } label: {
            Label("LanFi", systemImage: "wifi")
        }
        .menuBarExtraStyle(.window)
    }
}
