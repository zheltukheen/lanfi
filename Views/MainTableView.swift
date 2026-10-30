//
//  MainTableView.swift
//

import SwiftUI
import AppKit

struct MainTableView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @EnvironmentObject var uiState: AppUIState
    @EnvironmentObject var diagnostics: DiagnosticsViewModel
    @EnvironmentObject var interfaces: InterfacesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // UI State
    @State private var isResizingPanels = false
    @State private var showingLiveCapture = false
    @State private var showingRemoteSensors = false
    @State private var showingOfflineCapture = false

    // Resizable Panels State
    @State private var inspectorBaseWidth: CGFloat = 300
    @State private var inspectorDragOffset: CGFloat = 0

    // Высота нижней панели (увеличена по умолчанию)
    @State private var bottomPanelBaseHeight: CGFloat = 460
    @State private var bottomPanelDragOffset: CGFloat = 0

    // Вычисляемые размеры с ограничениями (min/max)
    var currentInspectorWidth: CGFloat {
        max(250, min(500, inspectorBaseWidth - inspectorDragOffset))
    }

    var currentBottomPanelHeight: CGFloat {
        max(150, min(600, bottomPanelBaseHeight - bottomPanelDragOffset))
    }

    private let sidebarWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 0) {

            // 1. TOOLBAR
            ToolbarView(
                viewModel: viewModel,
                showSidebar: $uiState.showSidebar,
                showInspector: $uiState.showInspector,
                customIntervalText: $uiState.customIntervalText,
                showingCustomIntervalAlert: $uiState.showingCustomIntervalAlert,
                showingLiveCapture: $showingLiveCapture,
                selectedBottomTab: $uiState.selectedBottomTab
            )

            // 2. CONTENT AREA
            // GeometryReader используется один раз для контекста
            GeometryReader { geo in
                VStack(spacing: 0) {

                    // A. TOP SECTION: Table + Inspector
                    HStack(spacing: 0) {
                        if uiState.showSidebar {
                            SidebarFilterView(viewModel: viewModel)
                                .frame(width: sidebarWidth)
                                .background(Material.regularMaterial)
                                .transition(.move(edge: .leading))

                            Rectangle()
                                .fill(Color(nsColor: .separatorColor))
                                .frame(width: 1)
                        }

                        // Table Area
                        VStack(spacing: 0) {
                            if let err = viewModel.errorMessage {
                                ErrorBanner(message: err, onClose: { viewModel.errorMessage = nil })
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

                            NetworkStatusBar(viewModel: viewModel)
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
                                            self.inspectorBaseWidth = self.currentInspectorWidth
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
                                    self.bottomPanelBaseHeight = self.currentBottomPanelHeight
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
                            case 2: InterfacesView(interfaces: interfaces)
                            case 3: RawDataView(viewModel: viewModel)
                            case 4: SpectrumView(viewModel: viewModel)
                            case 5: SignalHistoryView(viewModel: viewModel)
                            case 6: DiagnosticsView(diagnostics: diagnostics)
                            case 7: LiveCaptureView(viewModel: viewModel, embedded: true)
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
        .transaction { transaction in
            if isResizingPanels {
                transaction.disablesAnimations = true
            }
        }
        // Запрос прав при появлении
        .sheet(isPresented: $showingLiveCapture) {
            LiveCaptureView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingRemoteSensors) {
            RemoteSensorsView()
        }
        .sheet(isPresented: $showingOfflineCapture) {
            OfflineCaptureView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowLiveCapture)) { _ in
            showingLiveCapture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowRemoteSensors)) { _ in
            showingRemoteSensors = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowOfflineCapture)) { _ in
            showingOfflineCapture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiSelectBottomTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int { uiState.selectedBottomTab = tab }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowInspector)) { _ in
            uiState.showInspector = true
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
struct BottomPanelTabs: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer()

            TabGroup("OVERVIEW") {
                TabButton(
                    title: "Overview",
                    icon: "sparkles",
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )
            }

            groupDivider

            TabGroup("NETWORK") {
                TabButton(
                    title: "Profile",
                    icon: "square.stack.3d.up",
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Interfaces",
                    icon: "network",
                    isSelected: selectedTab == 2,
                    action: { selectedTab = 2 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Raw Data",
                    icon: "list.bullet.rectangle",
                    isSelected: selectedTab == 3,
                    action: { selectedTab = 3 }
                )
            }

            groupDivider

            TabGroup("RF") {
                TabButton(
                    title: "Spectrum",
                    icon: "waveform.path.ecg",
                    isSelected: selectedTab == 4,
                    action: { selectedTab = 4 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "History",
                    icon: "clock.arrow.circlepath",
                    isSelected: selectedTab == 5,
                    action: { selectedTab = 5 }
                )
            }

            groupDivider

            TabGroup("TROUBLESHOOT") {
                TabButton(
                    title: "Diagnostics",
                    icon: "stethoscope",
                    isSelected: selectedTab == 6,
                    action: { selectedTab = 6 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Capture",
                    icon: "record.circle",
                    isSelected: selectedTab == 7,
                    action: { selectedTab = 7 }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Material.bar)
    }

    private var groupDivider: some View {
        Divider()
            .frame(height: 30)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}

struct TabGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.secondary.opacity(0.75))
            HStack(spacing: 0) { content }
        }
        .padding(.horizontal, 5)
    }
}

struct BandFilterChip: View {
    let title: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(isOn ? color : .secondary)
                .frame(minWidth: 30, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isOn ? color.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isOn ? color.opacity(0.55) : Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter \(title)")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct TabButton: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Тулбар с унифицированными кнопками настроек
struct ToolbarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Binding var showSidebar: Bool
    @Binding var showInspector: Bool
    @Binding var customIntervalText: String
    @Binding var showingCustomIntervalAlert: Bool
    @Binding var showingLiveCapture: Bool
    @Binding var selectedBottomTab: Int
    @FocusState private var isSearchFocused: Bool
    @AppStorage("LanFi.toolbar.bands") private var showBands = true
    @AppStorage("LanFi.toolbar.search") private var showSearch = true
    @AppStorage("LanFi.toolbar.export") private var showExport = true
    @AppStorage("LanFi.toolbar.capture") private var showCapture = true

    private var primaryToolbarActions: some View {
        HStack(spacing: 10) {
            Button {
                selectedBottomTab = 7
            } label: {
                Label("Capture", systemImage: "record.circle").font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Packet capture")
            .accessibilityLabel("Open packet capture")

            Button {
                selectedBottomTab = 6
            } label: {
                Image(systemName: "stethoscope")
            }
            .buttonStyle(.borderless)
            .help("Diagnostics")
            .accessibilityLabel("Open diagnostics")

            Button {
                openWindow(id: "survey")
            } label: {
                Image(systemName: "map")
            }
            .buttonStyle(.borderless)
            .help("Site Survey")
            .accessibilityLabel("Open Site Survey")

            Menu {
                toolMenuItems
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver").font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Network tools")
        }
    }

    private var compactToolbarActions: some View {
        Menu {
            Button("Packet Capture") { selectedBottomTab = 7 }
            Button("Diagnostics") { selectedBottomTab = 6 }
            Button("Site Survey") { openWindow(id: "survey") }
            Divider()
            toolMenuItems
        } label: {
            Label("Actions", systemImage: "ellipsis.circle").font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var toolMenuItems: some View {
        Button("Live Capture (PCAP)…") { showingLiveCapture = true }
        Button("Analyze Packet Capture…") {
            NotificationCenter.default.post(name: .lanfiShowOfflineCapture, object: nil)
        }
        Button("Remote Sensors…") {
            NotificationCenter.default.post(name: .lanfiShowRemoteSensors, object: nil)
        }
        Divider()
        ForEach(
            ["Wi-Fi", "Network", "DNS", "LAN", "RF", "AP", "Wireless", "Security", "Throughput", "Advanced"],
            id: \.self
        ) { category in
            let tools = ToolCatalog.all.filter { $0.category == category }
            if !tools.isEmpty {
                Menu(category) {
                    ForEach(tools) { tool in
                        Button {
                            openWindow(id: "tool", value: tool.id)
                        } label: {
                            Label(tool.title, systemImage: tool.icon)
                        }
                    }
                }
            }
        }
        Divider()
        Button("LinkLiar — MAC spoofer…") {
            NSWorkspace.shared.open(URL(string: "https://github.com/halo/LinkLiar/releases")!)
        }
        Button("Wireshark…") {
            NSWorkspace.shared.open(URL(string: "https://www.wireshark.org/download.html")!)
        }
    }

    var body: some View {
        HStack(spacing: 16) {

            // 1. LEFT CONTROLS (Refresh & Settings)
            HStack(spacing: 10) {
                Button(action: {
                    if reduceMotion {
                        showSidebar.toggle()
                    } else {
                        withAnimation(.spring(response: 0.3)) { showSidebar.toggle() }
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .foregroundColor(showSidebar ? .accentColor : .primary)
                }
                .help("Toggle Filters Sidebar")
                .accessibilityLabel("Toggle filters sidebar")
                .buttonStyle(.borderless)
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // A. Кнопка Обновить
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Now")
                .accessibilityLabel("Refresh scan")
                .buttonStyle(.borderless)
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // B. Меню Настроек (Шестеренка) - унифицированный стиль
                Menu {
                    // Секция 1: Мониторинг
                    Section {
                        Picker(
                            "Scan Interval:",
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
                        Button("Custom Interval...") {
                            customIntervalText = String(Int(viewModel.refreshInterval))
                            showingCustomIntervalAlert = true
                        }
                    } header: {
                        Text("Monitoring")
                    }

                    Divider()

                    // Секция 2: Фильтры (слайдер сигнала)
                    Section {
                        Text("Min Signal: \(Int(viewModel.minSignalThreshold)) dBm")
                        Slider(value: $viewModel.minSignalThreshold, in: -100...(-30)) {
                            Text("Threshold")
                        }
                    } header: {
                        Text("Filters")
                    }

                    Divider()

                    // Секция 3: Отображение
                    Section {
                        Picker("Remove inactive after:", selection: $viewModel.removeAfterInterval) {
                            ForEach(NetworkRemovalInterval.allCases) { Text($0.title).tag($0) }
                        }

                        Picker("Signal Unit:", selection: $viewModel.signalDisplayMode) {
                            ForEach(SignalDisplayMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } header: {
                        Text("Display")
                    }

                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 50, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                .help("Settings & Monitoring Control")
            }

            // 3. Search
            if showSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .frame(minWidth: 100, maxWidth: 200)
                }
                .padding(5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }

            Spacer()
            if let connected = viewModel.connectedNetwork {
                HStack(spacing: 5) {
                    Image(systemName: "wifi").font(.caption2).foregroundColor(.green).accessibilityHidden(true)
                    Text(connected.displayName).font(.caption2).lineLimit(1)
                    Text("\(connected.signal) dBm").font(.caption2).foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.10))
                .clipShape(Capsule())
            }
            Text("\(viewModel.networks.count) networks")
                .font(.caption2)
                .foregroundColor(.secondary)

            // 4. Right Controls
            HStack(spacing: 12) {

                ViewThatFits(in: .horizontal) {
                    primaryToolbarActions
                    compactToolbarActions
                }

                // Export
                if showExport {
                    Menu {
                        Button("Export CSV…") { viewModel.exportCSV() }
                        Button("Export JSON…") { viewModel.exportJSON() }
                        if showCapture {
                            Divider()
                            Button("Live Capture (PCAP)…") { showingLiveCapture = true }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Export scan results")
                    .accessibilityLabel("Export scan results")
                }
                if showCapture {
                    Button {
                        showingLiveCapture = true
                    } label: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Live packet capture")
                    .accessibilityLabel("Live packet capture")
                }

                // Inspector Toggle
                Button(action: {
                    if reduceMotion {
                        showInspector.toggle()
                    } else {
                        withAnimation(.spring(response: 0.3)) { showInspector.toggle() }
                    }
                }) {
                    Image(systemName: "sidebar.right")
                        .foregroundColor(showInspector ? .accentColor : .primary)
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector")
                .accessibilityLabel("Toggle inspector")
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // Location Alert
                if !viewModel.isLocationAuthorized {
                    Button(action: {
                        viewModel.openSystemLocationSettings()
                    }) {
                        Image(systemName: "location.slash.fill")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Location Access Required")
                    .accessibilityLabel("Open location settings")
                }
            }
        }
        .padding(10)
        .background(Material.bar)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: .lanfiFocusSearch)) { _ in
            isSearchFocused = true
        }
    }
}

extension Notification.Name {
    static let lanfiFocusSearch = Notification.Name("LanFi.focusSearch")
    static let lanfiShowLiveCapture = Notification.Name("LanFi.showLiveCapture")
    static let lanfiShowRemoteSensors = Notification.Name("LanFi.showRemoteSensors")
    static let lanfiShowOfflineCapture = Notification.Name("LanFi.showOfflineCapture")
    static let lanfiSelectBottomTab = Notification.Name("LanFi.selectBottomTab")
    static let lanfiShowInspector = Notification.Name("LanFi.showInspector")
}

// MARK: - Subviews

struct ErrorBanner: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.callout).foregroundColor(.primary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
    }
}

struct NetworkInspectorView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Network Details").font(.headline)
                Spacer()
            }
            .padding()
            .background(Material.bar)

            Divider()

            ScrollView {
                if viewModel.selectedNetworkIds.count > 1 {
                    MultiSelectionInspector(viewModel: viewModel)
                } else if let network = viewModel.selectedNetwork {
                    VStack(alignment: .leading, spacing: 12) {

                        // Header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(viewModel.displayName(for: network))
                                    .font(.title2).bold()
                                    .foregroundColor(
                                        network.bssid == viewModel.currentConnectedBSSID ? .accentColor : .primary
                                    )
                                    .lineLimit(2)

                                HStack {
                                    Text(network.bssid.isEmpty ? "-" : network.bssid)
                                        .font(.caption).monospaced()
                                        .padding(4)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(4)
                                        .textSelection(.enabled)

                                    if network.bssid == viewModel.currentConnectedBSSID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .help("Currently Connected")
                                    }
                                }
                            }
                            Spacer()
                            SignalBadge(
                                rssi: network.signal,
                                label: viewModel.formatSignal(network.signal),
                                unit: viewModel.signalDisplayMode == .dbm ? "dBm" : ""
                            )
                        }

                        Divider()

                        // Quality, issues, history and utilization
                        if let metrics = viewModel.metrics(for: network) {
                            IssuesInspectorSection(network: network, metrics: metrics)
                            QualityInspectorSection(
                                metrics: metrics,
                                recommendation: viewModel.analysis.bestChannel(for: network.band)
                            )
                            if let advice = viewModel.channelAdvice(for: network) {
                                ChannelAdviceSection(advice: advice)
                            }
                            HistoryInspectorSection(network: network, viewModel: viewModel)
                            UtilizationInspectorSection(network: network, viewModel: viewModel)
                            ProximityBeaconInspectorSection(network: network)
                            ClientsInspectorSection(network: network)
                            MLOInspectorSection(network: network)
                            RegulatoryInspectorSection(network: network)
                            OtherRadiosInspectorSection()
                        }

                        GroupBox("Label & Notes") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(
                                    "Alias",
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).alias },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.alias = value
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                TextField(
                                    "Tags (comma separated)",
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).tags.joined(separator: ", ") },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.tags =
                                                value
                                                .split(separator: ",")
                                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                                .filter { !$0.isEmpty }
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                TextEditor(
                                    text: Binding(
                                        get: { viewModel.annotation(for: network).notes },
                                        set: { value in
                                            var annotation = viewModel.annotation(for: network)
                                            annotation.notes = value
                                            viewModel.updateAnnotation(annotation, for: network)
                                        }
                                    )
                                )
                                .font(.caption)
                                .frame(minHeight: 44, maxHeight: 70)
                                .scrollContentBackground(.hidden)
                                .background(Color.secondary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 5))

                                HStack(spacing: 8) {
                                    Text("Row color").font(.caption)
                                    ColorPicker(
                                        "",
                                        selection: Binding(
                                            get: {
                                                Color(
                                                    nsColor: ColorHex.color(
                                                        from: viewModel.annotation(for: network).colorHex ?? ""
                                                    ) ?? .clear
                                                )
                                            },
                                            set: { value in
                                                viewModel.setNetworkColor(
                                                    ColorHex.hex(from: NSColor(value)), for: network
                                                )
                                            }
                                        ),
                                        supportsOpacity: false
                                    )
                                    .labelsHidden()
                                    .frame(width: 34)
                                    Button("Clear") {
                                        viewModel.setNetworkColor("", for: network)
                                    }
                                    .controlSize(.mini)
                                }

                                Text("Saved locally on this Mac")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }

                        // Specs
                        GroupBox("Technical Specs") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "Channel", value: "\(network.channel)")
                                DetailRow(label: "Band", value: network.bandLabel)
                                DetailRow(
                                    label: "Width",
                                    value: network.channelWidthLabel == "-" ? "-" : "\(network.channelWidthLabel) MHz")
                                DetailRow(label: "Generation", value: network.generationLabel)
                                DetailRow(
                                    label: "Max Rate",
                                    value: network.maxRateLabel == "-" ? "-" : "\(network.maxRateLabel) Mbps")
                                DetailRow(label: "Vendor", value: network.vendor)
                                DetailRow(label: "Mode", value: network.mode)
                                if let noise = network.noise {
                                    DetailRow(label: "Noise", value: "\(noise) dBm")
                                }
                                if let snr = network.snr {
                                    DetailRow(label: "SNR", value: "\(snr) dB")
                                }

                                // Безопасное разворачивание
                                DetailRow(label: "Streams", value: network.streams.map { "\($0)" } ?? "-")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                        // Security
                        GroupBox("Security & Advanced") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "Protocol", value: network.security)
                                DetailRow(label: "Protection Mode", value: network.protectionMode ?? "Unknown")
                                DetailRow(label: "WPS", value: network.wps ?? "N/A")
                                DetailRow(
                                    label: "Fast Transition (802.11r)",
                                    value: network.fastTransition == true ? "Yes" : "No")
                                if let beacon = network.beaconInterval {
                                    DetailRow(label: "Beacon Interval", value: "\(beacon) ms")
                                }
                                if let cc = network.countryCode {
                                    DetailRow(label: "Country Code", value: cc)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                        // Timestamps
                        GroupBox("Activity") {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                                spacing: 12
                            ) {
                                DetailRow(label: "First Seen", value: formatDate(network.firstSeen))
                                DetailRow(label: "Last Seen", value: formatDate(network.lastSeen))
                                DetailRow(label: "Seen Ago", value: "\(network.seen) sec")
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                        }

                    }
                    .padding()
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wifi.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.2))
                        Text("Select a network to view details")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct EmptyScanView: View {
    var hasNetworks: Bool = false
    var hasActiveFilters: Bool = false
    var onClearFilters: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle" : "wifi.router")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.3))
            Text(hasActiveFilters ? "No matching networks" : "No networks found")
                .font(.headline)
            Text(
                hasActiveFilters
                    ? "Clear the search or filters to see all nearby networks."
                    : "Move closer to access points or refresh the scan."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if hasActiveFilters, let onClearFilters {
                Button("Clear Filters", action: onClearFilters)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .allowsHitTesting(hasActiveFilters)
    }
}

struct CompactPermissionBanner: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash.fill")
                .foregroundColor(.orange)
            Text("Location access is off — SSID/BSSID may be hidden. Other scan data still works.")
                .font(.caption)
            Spacer()
            Button("Allow") {
                viewModel.requestLocationAuthorization()
            }
            .controlSize(.small)
            Button("Settings") {
                viewModel.openSystemLocationSettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.1))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.2)), alignment: .bottom)
    }
}

struct LocationPermissionView: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Location access is required")
                .font(.title3.bold())
            Text(
                "macOS only reveals Wi-Fi network names (SSIDs) and access point identifiers (BSSIDs) to apps with Location Services enabled. LanFi uses this permission solely for scanning and never stores or transmits your location."
            )
            .font(.callout)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)

            HStack(spacing: 10) {
                Button("Allow Access") {
                    viewModel.requestLocationAuthorization()
                }
                .buttonStyle(.borderedProminent)

                Button("Open System Settings") {
                    viewModel.openSystemLocationSettings()
                }
                .buttonStyle(.bordered)

                Button("Check Again") {
                    viewModel.checkLocationAuthorization()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct NetworkStatusBar: View {
    @ObservedObject var viewModel: AnalyzerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Label("\(viewModel.networks.count) networks", systemImage: "wifi")
            if viewModel.groupMode != .none {
                Divider().frame(height: 10)
                Label("Grouped by \(viewModel.groupMode.title)", systemImage: "square.grid.2x2")
                    .foregroundColor(.accentColor)
            }
            Divider().frame(height: 10)
            Label("Avg quality \(viewModel.analysis.averageQuality)", systemImage: "gauge.with.dots.needle.50percent")
            if viewModel.analysis.criticalFindingCount > 0 {
                Divider().frame(height: 10)
                Label("\(viewModel.analysis.criticalFindingCount) critical", systemImage: "exclamationmark.shield.fill")
                    .foregroundColor(.red)
            }
            if let session = viewModel.loadedSession {
                Divider().frame(height: 10)
                Label("Session: \(session.displayName)", systemImage: "clock.arrow.circlepath")
                    .foregroundColor(.orange)
                Button("Resume Live") { viewModel.resumeLiveScan() }
                    .buttonStyle(.link)
                    .foregroundColor(.accentColor)
            }
            Spacer()
            if let lastScan = viewModel.lastScanDate {
                Text("Updated \(lastScan, style: .relative)")
                    .fixedSize()
            } else {
                Text("Waiting for first scan…")
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Material.bar)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .top)
    }
}

struct MultiSelectionInspector: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @State private var bulkAlias = ""
    @State private var bulkNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundColor(.accentColor)
                Text("\(viewModel.selectedNetworkIds.count) networks selected")
                    .font(.headline)
            }
            Text("Use ⌘-click or ⇧-click in the table to extend the selection.")
                .font(.caption)
                .foregroundColor(.secondary)

            let selected = viewModel.selectedNetworks
            VStack(alignment: .leading, spacing: 4) {
                ForEach(selected.prefix(8)) { network in
                    HStack {
                        Text(network.displaySSID).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(network.signal) dBm").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if selected.count > 8 {
                    Text("+ \(selected.count - 8) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Comparison").font(.caption.bold())
                NetworkComparisonTable(viewModel: viewModel, networks: selected)
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bulk annotation").font(.caption.bold())
                TextField("Alias for all selected", text: $bulkAlias)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes for all selected", text: $bulkNotes)
                    .textFieldStyle(.roundedBorder)
                Button("Apply to \(selected.count) selected") {
                    viewModel.applyBulkAnnotation(
                        alias: bulkAlias, notes: bulkNotes, to: viewModel.selectedNetworkIds
                    )
                }
                .controlSize(.small)
                .disabled(selected.isEmpty)
            }

            HStack {
                Button {
                    viewModel.copySelectedNetworks()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button {
                    viewModel.exportSelectedCSV()
                } label: {
                    Label("CSV", systemImage: "tablecells")
                }
                Button {
                    viewModel.exportSelectedJSON()
                } label: {
                    Label("JSON", systemImage: "curlybraces")
                }
            }
            .controlSize(.small)

            Button("Clear Selection") {
                viewModel.setSelection(ids: [], primary: nil)
            }
            .controlSize(.small)
        }
        .padding(14)
    }
}

struct QualityInspectorSection: View {
    let metrics: NetworkMetrics
    let recommendation: ChannelRecommendation?

    var body: some View {
        GroupBox("Quality") {
            VStack(alignment: .leading, spacing: 10) {
                QualityScoreView(score: metrics.qualityScore)
                ScoreRow(label: "Signal", score: metrics.signalScore)
                if let snr = metrics.snrScore {
                    ScoreRow(label: "SNR", score: snr)
                }
                ScoreRow(label: "Channel congestion", score: metrics.congestionScore)
                ScoreRow(label: "Security", score: metrics.securityScore)
                HStack {
                    Label("\(metrics.overlappingCount) overlapping", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Label("\(metrics.coChannelCount) co-channel", systemImage: "antenna.radiowaves.left.and.right")
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                if let recommendation {
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "wand.and.stars").foregroundColor(.accentColor)
                        Text(
                            "Best \(recommendation.band.label): channel \(recommendation.channel) · \(recommendation.widthMHz) MHz"
                        )
                        .font(.caption)
                        Spacer()
                        Text("\(recommendation.score)")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }

                if let issue = metrics.issues.first {
                    HStack(alignment: .top, spacing: 6) {
                        Image(
                            systemName: issue.severity == .critical
                                ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(issue.severity == .critical ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.caption.bold())
                            Text(issue.detail).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
    }
}

struct ChannelAdviceSection: View {
    let advice: ChannelAdvice

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Current ch \(advice.currentChannel) · \(advice.currentWidthMHz) MHz")
                        .font(.caption)
                    Spacer()
                    if let score = advice.currentScore {
                        Text("\(score)/100").font(.caption2).foregroundColor(.secondary)
                    }
                }
                if advice.shouldChange, let target = advice.recommendation {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.orange)
                        Text("Change to channel \(target.channel) · \(target.widthMHz) MHz")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(target.score)/100").font(.caption.bold()).foregroundColor(.green)
                    }
                    if target.isDFS {
                        Label("DFS channel — verify router/region support", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundColor(.orange)
                    }
                } else {
                    Label("Keep current channel", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundColor(.green)
                }
                Text(advice.reason).font(.caption2).foregroundColor(.secondary)
                if let model = advice.routerModel {
                    Text("Router model: \(model)").font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            .padding(4)
        } label: {
            Label("Channel recommendation", systemImage: "wand.and.stars")
        }
    }
}

struct SignalBadge: View {
    let rssi: Int
    let label: String
    let unit: String

    var color: Color {
        if rssi > -50 { return .green } else if rssi > -70 { return .yellow } else { return .red }
    }

    var body: some View {
        VStack {
            Text(label)
                .font(.title3).bold()
                .foregroundColor(color)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
