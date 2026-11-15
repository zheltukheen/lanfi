//
//  MainTableView.swift
//

import SwiftUI
import AppKit

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    /// Embedded inside the Network Toolkit, which is the app's main window.
    var embedded: Bool = false
    @EnvironmentObject var uiState: AppUIState
    @EnvironmentObject var toolkit: ToolkitViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    // UI State
    @State private var isResizingPanels = false
    @State private var showingHardwareSpectrum = false
    @State private var showingOfflineCapture = false
    @State private var showingRemoteSensors = false

    // Resizable panels — widths and heights survive relaunch.
    @AppStorage("LanFi.inspectorWidth") private var storedInspectorWidth: Double = 300
    @AppStorage("LanFi.bottomPanelHeight") private var storedBottomPanelHeight: Double = 460
    @State private var inspectorDragOffset: CGFloat = 0
    @State private var bottomPanelDragOffset: CGFloat = 0

    // Вычисляемые размеры с ограничениями (min/max)
    var currentInspectorWidth: CGFloat {
        max(250, min(500, CGFloat(storedInspectorWidth) - inspectorDragOffset))
    }

    var currentBottomPanelHeight: CGFloat {
        max(150, min(600, CGFloat(storedBottomPanelHeight) - bottomPanelDragOffset))
    }

    var body: some View {
        VStack(spacing: 0) {

            // 1. TOP ROW: toolbar, then the filter bar that replaced the sidebar
            ToolbarView(
                viewModel: viewModel,
                showInspector: $uiState.showInspector,
                customIntervalText: $uiState.customIntervalText,
                showingCustomIntervalAlert: $uiState.showingCustomIntervalAlert,
                selectedBottomTab: $uiState.selectedBottomTab
            )
            FilterBarView(viewModel: viewModel)

            // 2. CONTENT AREA
            // GeometryReader используется один раз для контекста
            GeometryReader { geo in
                VStack(spacing: 0) {

                    // A. TOP SECTION: Table + Inspector
                    HStack(spacing: 0) {
                        // Table Area
                        VStack(spacing: 0) {
                            if let err = viewModel.errorMessage {
                                ErrorBanner(message: err, onClose: { viewModel.errorMessage = nil })
                            }

                            if let session = viewModel.loadedSession {
                                HStack(spacing: 8) {
                                    Label("Session: \(session.displayName)", systemImage: "clock.arrow.circlepath")
                                        .foregroundColor(.orange)
                                    Button("Resume Live") { viewModel.resumeLiveScan() }
                                        .buttonStyle(.link)
                                    Spacer()
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.10))
                            }

                            if viewModel.isLocationAuthorized || !viewModel.networks.isEmpty {
                                VStack(spacing: 0) {
                                    if !viewModel.isLocationAuthorized {
                                        CompactPermissionBanner(viewModel: viewModel)
                                    }
                                    ZStack {
                                        WiFiTableView(viewModel: viewModel)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                                        if viewModel.networks.isEmpty && viewModel.errorMessage == nil {
                                            EmptyScanView(
                                                hasNetworks: viewModel.totalNetworkCount > 0,
                                                hasActiveFilters: viewModel.hasActiveFilters,
                                                onClearFilters: { viewModel.clearAllFilters() }
                                            )
                                        }
                                    }
                                }
                            } else {
                                LocationPermissionView(viewModel: viewModel)
                            }
                        }

                        // Inspector Area
                        if uiState.showInspector {
                            // Вертикальный разделитель (Resizer)
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                                .overlay(
                                    Rectangle().fill(Color.clear).frame(width: 9)
                                        .contentShape(Rectangle())
                                        .onHover { inside in
                                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                        }
                                )
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if !isResizingPanels { isResizingPanels = true }
                                            self.inspectorDragOffset = value.translation.width
                                        }
                                        .onEnded { _ in
                                            self.storedInspectorWidth = Double(self.currentInspectorWidth)
                                            self.inspectorDragOffset = 0
                                            self.isResizingPanels = false
                                        }
                                )
                                .zIndex(10)

                            NetworkInspectorView(viewModel: viewModel)
                                .frame(width: currentInspectorWidth)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .transition(.move(edge: .trailing))
                        }
                    }

                    // B. BOTTOM SECTION: Tabs + Charts

                    // Горизонтальный разделитель (Resizer)
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .overlay(
                            Rectangle().fill(Color.clear).frame(height: 9)
                                .contentShape(Rectangle())
                                .onHover { inside in
                                    if inside { NSCursor.resizeUp.push() } else { NSCursor.pop() }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    // Тянем вверх -> увеличиваем высоту (инверсия Y)
                                    if !isResizingPanels { isResizingPanels = true }
                                    self.bottomPanelDragOffset = value.translation.height
                                }
                                .onEnded { _ in
                                    self.storedBottomPanelHeight = Double(self.currentBottomPanelHeight)
                                    self.bottomPanelDragOffset = 0
                                    self.isResizingPanels = false
                                }
                        )
                        .zIndex(20)

                    // Bottom Container
                    VStack(spacing: 0) {

                        // Centered tabs (Insights / Spectrum / History / Raw Data)
                        BottomPanelTabs(selectedTab: $uiState.selectedBottomTab)

                        Divider()

                        // Контент графиков
                        ZStack {
                            Color(nsColor: .controlBackgroundColor).edgesIgnoringSafeArea(.all)

                            switch uiState.selectedBottomTab {
                            case 1: ProtocolsView(viewModel: viewModel)
                            case 3: RawDataView(viewModel: viewModel)
                            case 4: SpectrumView(viewModel: viewModel)
                            case 5: SignalHistoryView(viewModel: viewModel)
                            case 7: LiveCaptureView(viewModel: viewModel, embedded: true)
                            case 8: MonitorView(monitor: viewModel.monitor)
                            default: InsightsView(viewModel: viewModel)
                            }
                        }
                        .clipped()
                    }
                    .frame(height: min(currentBottomPanelHeight, max(240, geo.size.height * 0.6)))
                }
            }
        }
        // Алерт для ввода кастомного интервала
        .alert("Custom Interval", isPresented: $uiState.showingCustomIntervalAlert) {
            TextField("Seconds", text: $uiState.customIntervalText)
            Button("OK") {
                if let val = Double(uiState.customIntervalText), val > 0 {
                    viewModel.updateRefreshInterval(to: val)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter refresh interval in seconds:")
        }
        .sheet(isPresented: $showingHardwareSpectrum) {
            HardwareSpectrumView()
                .frame(minWidth: 980, minHeight: 620)
        }
        .sheet(isPresented: $showingOfflineCapture) {
            OfflineCaptureView(monitor: viewModel.monitor)
        }
        .sheet(isPresented: $showingRemoteSensors) {
            RemoteSensorsView()
        }
        .transaction { transaction in
            if isResizingPanels {
                transaction.disablesAnimations = true
            }
        }
        // Запрос прав при появлении
        .onReceive(NotificationCenter.default.publisher(for: .lanfiSelectBottomTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int { uiState.selectedBottomTab = tab }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowInspector)) { _ in
            uiState.showInspector = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowWiFiTool)) { note in
            switch note.userInfo?["tool"] as? String {
            case "spectrum": showingHardwareSpectrum = true
            case "analyze": showingOfflineCapture = true
            case "sensors": showingRemoteSensors = true
            default: break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowToolkit)) { note in
            if let raw = note.userInfo?["tool"] as? String,
                let tool = ToolboxTool(rawValue: raw)
            {
                toolkit.select(tool)
            }
        }
        .textSelection(.enabled)
        .onAppear {
            if !viewModel.isLocationAuthorized {
                viewModel.requestLocationAuthorization()
            }
        }
    }

}

// MARK: - Components

/// Нижняя панель с вкладками, выровненными по центру
