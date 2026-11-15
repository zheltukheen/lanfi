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
    @Binding var showInspector: Bool
    @Binding var customIntervalText: String
    @Binding var showingCustomIntervalAlert: Bool
    @Binding var selectedBottomTab: Int
    @FocusState private var isSearchFocused: Bool
    @AppStorage("LanFi.toolbar.search") private var showSearch = true
    @AppStorage("LanFi.toolbar.export") private var showExport = true

    private var primaryToolbarActions: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(
                    name: .lanfiShowToolkit, object: nil,
                    userInfo: ["tool": ToolboxTool.internetCheck.rawValue])
            } label: {
                Image(systemName: "stethoscope")
            }
            .buttonStyle(.borderless)
            .help("Diagnostics")
            .accessibilityLabel("Open diagnostics")

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
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .help(
                viewModel.isAutoScanPaused
                    ? "Auto-scan is paused"
                    : "Time until the next scan (\(Int(viewModel.refreshInterval)) s interval)"
            )
            .accessibilityLabel("Refresh countdown")
        }
    }

    private func remainingUntilRefresh(at date: Date) -> Double {
        let interval = max(0.5, viewModel.refreshInterval)
        guard let last = viewModel.lastScanDate else { return interval }
        return max(0, last.addingTimeInterval(interval).timeIntervalSince(date))
    }

    private var compactToolbarActions: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(
                    name: .lanfiShowToolkit, object: nil,
                    userInfo: ["tool": ToolboxTool.internetCheck.rawValue])
            } label: {
                Image(systemName: "stethoscope")
            }
            .buttonStyle(.borderless)
            .help("Diagnostics")
            .accessibilityLabel("Open diagnostics")

        }
    }

    /// Hardware-only screens that need analyzer context or a full-size window:
    /// they open as sheets from the analyzer rather than as toolkit sections.
    private var wifiToolsMenu: some View {
        Menu {
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
            HStack(spacing: 10) {
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

                // A2. Пауза/возобновление автопересканирования
                Button(action: { viewModel.isAutoScanPaused.toggle() }) {
                    Image(systemName: viewModel.isAutoScanPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(viewModel.isAutoScanPaused ? .accentColor : .primary)
                }
                .help(viewModel.isAutoScanPaused ? "Resume Auto-Scan" : "Pause Auto-Scan")
                .accessibilityLabel(viewModel.isAutoScanPaused ? "Resume auto-scan" : "Pause auto-scan")
                .buttonStyle(.borderless)
                .frame(width: 36, height: 28)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                // A3. Отсчёт до следующего автосканирования
                refreshCountdown

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

                wifiToolsMenu

                ViewThatFits(in: .horizontal) {
                    primaryToolbarActions
                    compactToolbarActions
                }

                // Export
                if showExport {
                    Menu {
                        Button("Export CSV…") { viewModel.exportCSV() }
                        Button("Export JSON…") { viewModel.exportJSON() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Export scan results")
                    .accessibilityLabel("Export scan results")
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
