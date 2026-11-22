import LanFiCore
import AppKit
import SwiftUI

struct NetworkToolkitView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    /// Passed explicitly instead of read from the environment: previews, the
    /// snapshot harness and the smoke test build this view without the app's
    /// environment, and the dashboard must still have a meter to read.
    @ObservedObject var meter: MenuBarMeterModel = .shared
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel
    @EnvironmentObject private var interfaces: InterfacesViewModel
    @EnvironmentObject private var uptime: UptimeMonitor
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var survey: SurveyViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var showingPalette = false
    @AppStorage(AppSettingsKey.toolkitSidebarWidth.rawValue) private var storedSidebarWidth: Double = 228
    @State private var sidebarDragOffset: CGFloat = 0

    private var currentSidebarWidth: CGFloat {
        max(180, min(360, CGFloat(storedSidebarWidth) + sidebarDragOffset))
    }

    private var searchResults: [ToolboxTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return ToolboxTool.allCases.filter { tool in
            tool.showsInSidebar
                && (tool.title.localizedCaseInsensitiveContains(query)
                    || tool.section.title.localizedCaseInsensitiveContains(query)
                    || tool.plannedDetail.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            sidebarResizer
            VStack(spacing: 0) {
                if !isWorkspaceTool {
                    detailHeader
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: DesignToken.Layout.windowMinWidth,
            minHeight: DesignToken.Layout.windowMinHeight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .appTableDensity()
        .background {
            if #available(macOS 14.0, *) {
                SettingsOpenerRegistration()
            }
        }
        .sheet(isPresented: $showingPalette) {
            CommandPaletteView { item in
                perform(item)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowCommandPalette)) { _ in
            showingPalette = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowToolkit)) { note in
            if let raw = note.userInfo?["tool"] as? String,
                let tool = ToolboxTool(rawValue: raw)
            {
                toolkit.select(tool)
            }
        }
        .onAppear {
            MCPLiveActionService.shared.configure(
                analyzer: analyzer, survey: survey, interfaces: interfaces)
            if MCPLiveActionService.shared.isEnabled {
                MCPLiveActionService.shared.start()
            }
            #if DEBUG
                ToolkitSnapshot.captureIfRequested(
                    toolkit: toolkit, analyzer: analyzer, survey: survey, uptime: uptime)
            #endif
        }
    }

    /// The Wi-Fi workspace brings its own toolbar, so it does not need the
    /// generic tool header above it.
    private var isWorkspaceTool: Bool {
        toolkit.selection.screen == .wifiAnalyzer
    }

    /// Runs the destination of a palette entry. Settings opens the page the
    /// system Settings window reads from, because the window itself has no
    /// programmatic selection API on macOS 13.
    private func perform(_ item: CommandItem) {
        switch item.destination {
        case .tool(let tool):
            toolkit.select(tool)
        case .wifiTab(let tab):
            toolkit.select(.wifiAnalyzer)
            NotificationCenter.default.post(
                name: .lanfiSelectBottomTab, object: nil, userInfo: ["tab": tab])
        case .settings(let section):
            SettingsRouter.shared.open(section)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(ToolboxSection.allCases) { section in
                            sectionHeader(section.title)
                            ForEach(
                                ToolboxTool.allCases.filter {
                                    $0.section == section && $0.showsInSidebar
                                }
                            ) { tool in
                                toolRow(tool)
                            }
                        }
                    } else {
                        sectionHeader(String(localized: "Results"))
                        if searchResults.isEmpty {
                            Text("No tools found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, DesignToken.Spacing.compact)
                                .padding(.vertical, DesignToken.Spacing.small)
                        } else {
                            ForEach(searchResults) { tool in
                                toolRow(tool)
                            }
                        }
                    }
                }
                .padding(DesignToken.Spacing.small)
            }
        }
        .frame(width: currentSidebarWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebarResizer: some View {
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
                    .onChanged { value in sidebarDragOffset = value.translation.width }
                    .onEnded { _ in
                        storedSidebarWidth = Double(currentSidebarWidth)
                        sidebarDragOffset = 0
                    }
            )
            .zIndex(10)
    }

    private var searchField: some View {
        AppSearchField(placeholder: "Search tools", text: $searchText)
            .padding(.horizontal, DesignToken.Spacing.small)
            .padding(.top, DesignToken.Spacing.small)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, DesignToken.Spacing.compact)
            .padding(.top, DesignToken.Spacing.card)
            .padding(.bottom, DesignToken.Spacing.tight)
    }

    private func toolRow(_ tool: ToolboxTool) -> some View {
        AppListRow(
            icon: tool.icon,
            title: tool.title,
            trailingText: tool.isAvailable ? nil : String(localized: "Soon"),
            isSelected: toolkit.selection == tool,
            isEnabled: tool.isAvailable,
            help: tool.isAvailable ? tool.title : tool.plannedDetail
        ) {
            toolkit.select(tool)
        }
    }

    private var detailHeader: some View {
        ToolkitHeaderBar {
            HStack(spacing: DesignToken.Spacing.compact) {
                Image(systemName: toolkit.selection.icon)
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(toolkit.selection.title)
                        .font(.title3.bold())
                    Text(toolkit.selection.section.title)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } trailing: {
            AppIconButton(
                systemImage: "questionmark.circle",
                label: "Open LanFi Help",
                tint: .secondary
            ) {
                openWindow(id: "help")
            }
        }
    }

    /// The route comes from the registry (`ToolDescriptor.screen`), so a tool
    /// that shares a screen with another (`Sockets`/`Traffic`) is routed once.
    @ViewBuilder
    private var detail: some View {
        switch toolkit.selection.screen {
        case .overview:
            OverviewDashboardView(toolkit: toolkit, meter: meter)
        case .internetCheck:
            InternetCheckToolView(diagnostics: diagnostics, speedTest: toolkit.speedTest)
        case .ping:
            PingToolView(model: toolkit.ping)
        case .visualTraceroute:
            TracerouteTabsView(
                visual: toolkit.visualTraceroute, mtr: toolkit.mtr, toolkit: toolkit)
        case .speedTest:
            SpeedTestToolView(model: toolkit.speedTest)
        case .dnsLookup:
            DNSToolView(
                model: toolkit.dns, propagation: toolkit.dnsPropagation, toolkit: toolkit)
        case .whoisGeoIP:
            WhoisGeoIPToolView(whois: toolkit.whois, geo: toolkit.geoIP, toolkit: toolkit)
        case .sslCertificate:
            SSLToolView(model: toolkit.ssl)
        case .portScan:
            PortScanToolView(model: toolkit.portScan)
        case .natTest:
            NATToolView(model: toolkit.nat)
        case .pathCheck:
            PathCheckToolView(model: toolkit.pathCheck)
        case .subnetCalculator:
            SubnetToolView(model: toolkit.subnet)
        case .networkMonitor:
            NetworkMonitorToolView(interfaces: interfaces)
        case .uptimeMonitor:
            UptimeToolView(monitor: uptime)
        case .routeMonitor:
            RouteMonitorToolView(monitor: RouteMonitor.shared)
        case .lanScanner:
            LANScannerToolView(model: toolkit.lanScanner)
        case .iperf3:
            Iperf3ToolView(model: toolkit.iperf3)
        case .httpTraffic:
            HTTPTrafficToolView(model: toolkit.httpTraffic)
        case .connections:
            ConnectionsToolView(toolkit: toolkit)
        case .advancedTools:
            AdvancedToolsToolView()
        case .wifiAnalyzer:
            WiFiAnalyzerToolView()
        case .roamingTest:
            RoamingTestToolView(analyzer: analyzer)
        case .knownNetworks:
            KnownNetworksToolView(analyzer: analyzer)
        case .securityWatch:
            SecurityWatchToolView(analyzer: analyzer, monitor: analyzer.monitor)
        case .clientAnalytics:
            ClientAnalyticsToolView(analyzer: analyzer)
        case .siteSurvey:
            SurveyView(analyzer: analyzer, survey: survey)
        case .gpsMap:
            GPSMapToolView(analyzer: analyzer)
        }
    }
}
