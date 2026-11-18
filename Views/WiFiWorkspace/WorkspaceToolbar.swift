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

    /// Shows which CoreWLAN interface the scanner will use. The choice lives in
    /// Settings → Wi-Fi; when it is the system default, the name still appears
    /// so multi-radio Macs are never ambiguous.
    private var scanningWithLabel: some View {
        Group {
            if let interfaceName = WiFiInterfaceCatalog.activeName() {
                HStack(spacing: DesignToken.Spacing.tight) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Scanning with \(interfaceName)")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)
                .help("Scan interface. Change it in Settings → Wi-Fi.")
                .accessibilityLabel("Scanning with interface \(interfaceName)")
            }
        }
    }

    /// Time until the next automatic scan, right next to Refresh/Pause so the
    /// analyzer shows how long the current list is good for.
    private var refreshCountdown: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = remainingUntilRefresh(at: context.date)
            HStack(spacing: 4) {
                Image(systemName: viewModel.isAutoScanPaused ? "pause.fill" : "clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(
                    viewModel.isAutoScanPaused
                        ? "Paused"
                        : String(format: "%.1f s", remaining)
                )
                .font(.caption2.monospacedDigit())
            }
            .foregroundColor(
                viewModel.isAutoScanPaused
                    ? .secondary
                    : (remaining <= 1 ? .accentColor : .secondary)
            )
            .padding(.horizontal, DesignToken.Spacing.small)
            .frame(height: DesignToken.Toolbar.height)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(DesignToken.Radius.control)
            .overlay(
                RoundedRectangle(cornerRadius: DesignToken.Radius.control)
                    .stroke(
                        Color.secondary.opacity(DesignToken.Toolbar.strokeOpacity),
                        lineWidth: DesignToken.Stroke.hairline)
            )
            .help(
                viewModel.isAutoScanPaused
                    ? "Auto-scan is paused"
                    : "Time until the next scan (\(Int(viewModel.refreshInterval)) s interval)"
            )
            .accessibilityLabel("Refresh countdown")
        }
    }

    /// P0.2 mode picker. Passive and directed open the plan sheet because they
    /// are on-demand runs rather than the background scan.
    private var scanModePicker: some View {
        Picker(
            "Scan mode",
            selection: Binding(
                get: { passiveScan.mode },
                set: { mode in
                    viewModel.selectScanMode(mode)
                    if mode != .active { showingScanModes = true }
                })
        ) {
            ForEach(ScanMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Scan mode: active, passive or directed")
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
            Label("Wi-Fi Tools", systemImage: "wrench.and.screwdriver")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Spectrum, capture analysis and remote sensors")
    }

    private func postWiFiTool(_ tool: String) {
        NotificationCenter.default.post(
            name: .lanfiShowWiFiTool, object: nil, userInfo: ["tool": tool])
    }

    var body: some View {
        HStack(spacing: 16) {

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

                // A3. Отсчёт до следующего автосканирования
                refreshCountdown

                scanningWithLabel

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
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .frame(width: DesignToken.Toolbar.iconWidth + 8)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                        .frame(minWidth: 100, maxWidth: 200)
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
            Text("\(viewModel.networks.count) networks")
                .font(.caption2)
                .foregroundColor(.secondary)

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
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: DesignToken.Toolbar.iconWidth - 8)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
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
    }
}
