//  LanFiApp.swift
import SwiftUI

@main
struct LanFiApp: App {
    // ViewModel создается здесь и живет все время работы приложения
    @StateObject private var viewModel = AnalyzerViewModel()
    @StateObject private var uiState = AppUIState()
    @StateObject private var diagnostics = DiagnosticsViewModel()
    @StateObject private var updater = UpdaterController()
    @StateObject private var survey = SurveyViewModel()
    @StateObject private var interfaces = InterfacesViewModel()

    // Свойство для отслеживания состояния приложения (активно/фон)
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            MainTableView(viewModel: viewModel)
                .frame(minWidth: 900, minHeight: 600)
                .environmentObject(uiState)
                .environmentObject(diagnostics)
                .environmentObject(interfaces)
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
        }

        MenuBarExtra {
            MenuBarView(viewModel: viewModel, diagnostics: diagnostics)
        } label: {
            Label("LanFi", systemImage: "wifi")
        }
        .menuBarExtraStyle(.window)
    }
}
