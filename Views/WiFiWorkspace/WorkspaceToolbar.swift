import LanFiCore
import AppKit
import SwiftUI

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
                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                        .fill(isOn ? color.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                        .stroke(isOn ? color.opacity(0.55) : Color.secondary.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter \(title)")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// One chip of the scan-mode row. It borrows the table's band-filter look —
/// the app's established style for a set of exclusive toggles — instead of a
/// native popup button.
struct ScanModeChip: View {
    let mode: ScanMode
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(mode.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundColor(isOn ? .accentColor : .secondary)
                .padding(.horizontal, DesignToken.Spacing.tight)
                .frame(minWidth: 30, minHeight: DesignToken.Toolbar.height)
                .fixedSize()
                .background(
                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                        .fill(
                            isOn
                                ? Color.accentColor.opacity(0.16)
                                : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                        .stroke(
                            isOn
                                ? Color.accentColor.opacity(0.55)
                                : Color.secondary.opacity(0.18),
                            lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.title)
        .accessibilityLabel(Text(mode.title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Тулбар с унифицированными кнопками настроек
struct ToolbarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var passiveScan: PassiveScanViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showInspector: Bool
    @Binding var customIntervalText: String
    @Binding var showingCustomIntervalAlert: Bool
    @Binding var selectedBottomTab: Int
    @Binding var showingScanModes: Bool
    @FocusState private var isSearchFocused: Bool
    @AppStorage(AppSettingsKey.toolbarSearch.rawValue) private var showSearch = true
    @AppStorage(AppSettingsKey.toolbarExport.rawValue) private var showExport = true
    /// True while the interval popover is on screen. The countdown checks it and
    /// swaps the 0.5 s `TimelineView` for a frozen label, so the open list is not
    /// relaid out twice a second underneath the pointer.
    @State private var isRefreshMenuOpen = false
    @State private var menuOpenedAt = Date()
    @State private var isRefreshHovering = false
    /// The countdown is driven by a value, not by a `TimelineView` inside the
    /// button's label: a label that rebuilt itself twice a second gave the
    /// popover a new anchor, so a click could open and immediately dismiss it.
    @State private var countdownTick = Date()
    private let countdown = Timer.publish(every: 0.5, on: .main, in: .common)
        .autoconnect()

    private var diagnosticsButton: some View {
        ToolbarIconButton(
            systemImage: "stethoscope",
            label: "Open diagnostics",
            help: "Diagnostics"
        ) {
            NotificationCenter.default.post(
                name: .lanfiShowToolkit, object: nil,
                userInfo: ["tool": ToolboxTool.internetCheck.rawValue])
        }
    }

    /// Scan interface picker: any CoreWLAN radio macOS exposes can be used, so
    /// the label is a menu instead of a static caption. The choice is persisted
    /// where `WiFiScanner` and `PassiveScanEngine` read it, and selecting an
    /// adapter restarts the loop so the next scan uses the new radio.
    private var scanInterfaceMenu: some View {
        Menu {
            Picker("Scan interface", selection: scanInterfaceBinding) {
                Text("System default").tag("")
                ForEach(WiFiInterfaceCatalog.names(), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
        } label: {
            AppMenuLabel(
                title: preferredInterface.map { String(localized: "Scanning with \($0)") }
                    ?? String(localized: "System default interface"),
                systemImage: "antenna.radiowaves.left.and.right",
                isActive: preferredInterface != nil)
        }
        .appMenuStyle()
        .help("Scan interface. Pick any Wi-Fi adapter macOS exposes.")
        .accessibilityLabel("Scan interface")
        .accessibilityValue(preferredInterface ?? String(localized: "System default"))
    }

    private var preferredInterface: String? {
        let value = UserDefaults.standard.string(forKey: AppSettingsKey.wifiInterface.rawValue)
        return (value?.isEmpty ?? true) ? nil : value
    }

    private var scanInterfaceBinding: Binding<String> {
        Binding(
            get: { preferredInterface ?? "" },
            set: { viewModel.selectScanInterface($0.isEmpty ? nil : $0) })
    }

    /// Preset cadences offered by the countdown menu; the current value is
    /// checked, and anything else is shown as "Custom".
    private static let presetIntervals: [Double] = [1, 3, 5, 10, 30, 60]

    /// The countdown pill is the interval menu: clicking it sets the scan
    /// cadence, opens the custom-interval sheet, or pauses auto-scan.
    private var refreshMenu: some View {
        // A popover instead of a native `Menu`: a menu tracks the mouse on its
        // own run loop, so an animated label inside it makes the list jump and
        // can dismiss it. The popover also gives us an explicit `isPresented`,
        // which is what stops the timer while the list is open.
        Button {
            menuOpenedAt = Date()
            isRefreshMenuOpen.toggle()
        } label: {
            refreshCountdown
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isRefreshMenuOpen, arrowEdge: .bottom) {
            refreshMenuContent
        }
        .help(
            viewModel.isAutoScanPaused
                ? "Auto-scan is paused. Click to choose the refresh interval."
                : "Refresh every \(Int(viewModel.refreshInterval)) s. Click to change the frequency."
        )
        .accessibilityLabel("Refresh interval")
        .accessibilityValue(
            viewModel.isAutoScanPaused ? "Paused" : "\(Int(viewModel.refreshInterval)) seconds")
    }

    /// Contents of the interval popover. Every row closes the popover, so a
    /// choice applies once and the frozen countdown resumes on dismissal.
    private var refreshMenuContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Refresh interval")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, DesignToken.Spacing.compact)
                .padding(.bottom, 2)
            ForEach(Self.presetIntervals, id: \.self) { value in
                AppListRow(
                    title: intervalLabel(value),
                    isSelected: abs(viewModel.refreshInterval - value) < 0.01
                ) {
                    viewModel.updateRefreshInterval(to: value)
                    isRefreshMenuOpen = false
                }
            }
            Divider().padding(.vertical, DesignToken.Spacing.tight)
            AppListRow(icon: "slider.horizontal.3", title: String(localized: "Custom Interval...")) {
                isRefreshMenuOpen = false
                customIntervalText = String(Int(viewModel.refreshInterval))
                showingCustomIntervalAlert = true
            }
            AppListRow(
                icon: viewModel.isAutoScanPaused ? "play.fill" : "pause.fill",
                title: viewModel.isAutoScanPaused
                    ? String(localized: "Resume auto-scan") : String(localized: "Pause auto-scan")
            ) {
                viewModel.isAutoScanPaused.toggle()
                isRefreshMenuOpen = false
            }
        }
        .padding(DesignToken.Spacing.small)
        .frame(width: 220)
    }

    private func intervalLabel(_ value: Double) -> String {
        let seconds = Int(value)
        if abs(viewModel.refreshInterval - value) < 0.01 {
            return "\(seconds) s (current)"
        }
        return "\(seconds) s"
    }

    /// Time until the next automatic scan, right next to Refresh/Pause so the
    /// analyzer shows how long the current list is good for.
    ///
    /// The timeline only runs while the popover is closed. The figure is whole
    /// seconds in a fixed-width, monospaced slot and is followed by a chevron,
    /// so the control keeps one size on every tick and reads as clickable even
    /// though the native menu indicator is gone.
    private var refreshCountdown: some View {
        countdownLabel(at: isRefreshMenuOpen ? menuOpenedAt : countdownTick)
    }

    private func countdownLabel(at date: Date) -> some View {
        let remaining = remainingUntilRefresh(at: date)
        let paused = viewModel.isAutoScanPaused
        return HStack(spacing: 4) {
            Image(systemName: paused ? "pause.fill" : "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(paused ? String(localized: "Paused") : String(format: "%.0f s", remaining))
                .font(.caption2.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(
            paused ? .secondary : (remaining <= 1 ? .accentColor : .secondary)
        )
        .padding(.horizontal, DesignToken.Spacing.small)
        .frame(height: DesignToken.Toolbar.height)
        .background(
            isRefreshHovering
                ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)
        )
        .cornerRadius(DesignToken.Radius.control)
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                .stroke(
                    isRefreshHovering
                        ? Color.accentColor.opacity(0.6)
                        : Color.secondary.opacity(DesignToken.Toolbar.strokeOpacity),
                    lineWidth: DesignToken.Stroke.hairline)
        )
        .contentShape(Rectangle())
        .onHover { isRefreshHovering = $0 }
        .accessibilityHidden(true)
    }

    /// P0.2 mode picker. Passive and directed open the plan sheet because they
    /// are on-demand runs rather than the background scan.
    /// Modal picker replaced by a menu so it matches every other dropdown; the
    /// current mode is the label and a checkmark marks it in the list.
    private var scanModePicker: some View {
        HStack(spacing: DesignToken.Spacing.tight) {
            ForEach(ScanMode.allCases) { mode in
                ScanModeChip(mode: mode, isOn: passiveScan.mode == mode) {
                    viewModel.selectScanMode(mode)
                    if mode != .active { showingScanModes = true }
                }
            }
        }
        .help("Scan mode: active, passive or directed")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan mode")
    }

    private func remainingUntilRefresh(at date: Date) -> Double {
        let interval = max(0.5, viewModel.refreshInterval)
        guard let last = viewModel.lastScanDate else { return interval }
        return max(0, last.addingTimeInterval(interval).timeIntervalSince(date))
    }

    /// Hardware-only screens that need analyzer context or a full-size window:
    /// they open as sheets from the analyzer rather than as toolkit sections.
    private var wifiToolsMenu: some View {
        Menu {
            Button("Scan Mode & Channel Plan…") { postWiFiTool("scanModes") }
            Divider()
            Button("Hardware Spectrum…") { postWiFiTool("spectrum") }
            Button("Analyze Capture…") { postWiFiTool("analyze") }
            Button("Remote Sensors…") { postWiFiTool("sensors") }
        } label: {
            AppMenuLabel(title: "Wi-Fi Tools", systemImage: "wrench.and.screwdriver")
        }
        .appMenuStyle()
        .help("Spectrum, capture analysis and remote sensors")
    }

    private func postWiFiTool(_ tool: String) {
        NotificationCenter.default.post(
            name: .lanfiShowWiFiTool, object: nil, userInfo: ["tool": tool])
    }

    var body: some View {
        HStack(spacing: DesignToken.Spacing.medium) {

            // 1. LEFT CONTROLS (Refresh & Settings)
            HStack(spacing: DesignToken.Toolbar.spacing) {
                ToolbarIconButton(
                    systemImage: "arrow.clockwise",
                    label: "Refresh scan",
                    help: "Refresh now"
                ) {
                    viewModel.refresh()
                }

                ToolbarIconButton(
                    systemImage: viewModel.isAutoScanPaused ? "play.fill" : "pause.fill",
                    label: viewModel.isAutoScanPaused ? "Resume auto-scan" : "Pause auto-scan",
                    help: viewModel.isAutoScanPaused ? "Resume auto-scan" : "Pause auto-scan",
                    isActive: viewModel.isAutoScanPaused
                ) {
                    viewModel.isAutoScanPaused.toggle()
                }

                // A3. Отсчёт до следующего автосканирования + меню частоты
                refreshMenu

                scanInterfaceMenu

                scanModePicker

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
                    AppIconMenuLabel(systemImage: "gearshape")
                }
                .appMenuStyle()
                .appToolbarChrome()
                .help("Settings & Monitoring Control")
                .accessibilityLabel("Scan settings")
            }

            // 3. Search
            if showSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .frame(minWidth: 90, maxWidth: 140)
                }
                .padding(DesignToken.Spacing.tight)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(DesignToken.Radius.control)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignToken.Radius.control).stroke(
                        Color.secondary.opacity(DesignToken.Toolbar.strokeOpacity),
                        lineWidth: DesignToken.Stroke.hairline))
            }

            Spacer()
            if let connected = viewModel.connectedNetwork {
                HStack(spacing: 5) {
                    Image(systemName: "wifi").font(.caption2).foregroundColor(.green).accessibilityHidden(true)
                    Text(connected.displayName).font(.caption2).lineLimit(1)
                    Text("\(connected.signal) dBm").font(.caption2).foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.small)
                .padding(.vertical, DesignToken.Spacing.tight)
                .background(Color.green.opacity(0.10))
                .clipShape(Capsule())
            }

            // 4. Right Controls
            HStack(spacing: 12) {

                wifiToolsMenu

                diagnosticsButton

                // Export
                if showExport {
                    Menu {
                        Button("Export CSV…") { viewModel.exportCSV() }
                        Button("Export JSON…") { viewModel.exportJSON() }
                    } label: {
                        AppIconMenuLabel(systemImage: "square.and.arrow.up")
                    }
                    .appMenuStyle()
                    .appToolbarChrome()
                    .help("Export scan results")
                    .accessibilityLabel("Export scan results")
                }
                // Inspector Toggle
                ToolbarIconButton(
                    systemImage: "sidebar.right",
                    label: "Toggle inspector",
                    help: "Toggle Inspector",
                    isActive: showInspector
                ) {
                    if reduceMotion {
                        showInspector.toggle()
                    } else {
                        withAnimation(.spring(response: 0.3)) { showInspector.toggle() }
                    }
                }

                // Location Alert
                if !viewModel.isLocationAuthorized {
                    ToolbarIconButton(
                        systemImage: "location.slash.fill",
                        label: "Open location settings",
                        help: "Location access required",
                        tint: AppPalette.warning
                    ) {
                        viewModel.openSystemLocationSettings()
                    }
                }
            }
        }
        .padding(DesignToken.Spacing.compact)
        .background(Material.bar)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: .lanfiFocusSearch)) { _ in
            isSearchFocused = true
        }
        .onReceive(countdown) { date in
            if !isRefreshMenuOpen { countdownTick = date }
        }
    }
}
