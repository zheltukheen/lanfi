import LanFiCore
import AppKit
import SwiftUI

struct NetworkToolkitView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel
    @EnvironmentObject private var interfaces: InterfacesViewModel
    @EnvironmentObject private var uptime: UptimeMonitor
    @EnvironmentObject private var analyzer: AnalyzerViewModel
    @EnvironmentObject private var survey: SurveyViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
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
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .appTableDensity()
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowToolkit)) { note in
            if let raw = note.userInfo?["tool"] as? String,
                let tool = ToolboxTool(rawValue: raw)
            {
                toolkit.select(tool)
            }
        }
        .onAppear {
            #if DEBUG
                ToolkitSnapshot.captureIfRequested(
                    toolkit: toolkit, analyzer: analyzer, survey: survey, uptime: uptime)
            #endif
        }
    }

    /// The Wi-Fi workspace brings its own toolbar, so it does not need the
    /// generic tool header above it.
    private var isWorkspaceTool: Bool {
        toolkit.selection == .wifiAnalyzer
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
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Search tools", text: $searchText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .padding(.vertical, DesignToken.Spacing.tight)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: DesignToken.Radius.control))
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
        let selected = toolkit.selection == tool
        return Button {
            toolkit.select(tool)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tool.icon)
                    .font(.system(size: 12))
                    .frame(width: 17)
                Text(tool.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !tool.isAvailable {
                    Text("Soon")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, DesignToken.Spacing.tight)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, DesignToken.Spacing.small)
            .padding(.vertical, DesignToken.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(
                selected ? .white : (tool.isAvailable ? .primary : .secondary)
            )
            .background(
                selected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignToken.Radius.control)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tool.isAvailable)
        .help(tool.isAvailable ? tool.title : tool.plannedDetail)
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
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
            Spacer()
            ToolbarIconButton(
                systemImage: "questionmark.circle",
                label: "Open LanFi Help",
                help: "LanFi Help",
                tint: .secondary
            ) {
                openWindow(id: "help")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, DesignToken.Spacing.compact)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch toolkit.selection {
        case .internetCheck:
            InternetCheckToolView(diagnostics: diagnostics, speedTest: toolkit.speedTest)
        case .ping:
            PingToolView(model: toolkit.ping)
        case .traceroute:
            TracerouteToolView(model: toolkit.traceroute)
        case .mtr:
            MTRToolView(model: toolkit.mtr)
        case .visualTraceroute:
            VisualTracerouteToolView(model: toolkit.visualTraceroute)
        case .speedTest:
            SpeedTestToolView(model: toolkit.speedTest)
        case .dnsLookup:
            DNSToolView(model: toolkit.dns)
        case .dnsPropagation:
            DNSPropagationToolView(model: toolkit.dnsPropagation)
        case .whois:
            WhoisToolView(model: toolkit.whois)
        case .geoIP:
            GeoIPToolView(model: toolkit.geoIP)
        case .sslCertificate:
            SSLToolView(model: toolkit.ssl)
        case .portScan:
            PortScanToolView(model: toolkit.portScan)
        case .pathCheck:
            PathCheckToolView(model: toolkit.pathCheck)
        case .subnetCalculator:
            SubnetToolView(model: toolkit.subnet)
        case .networkMonitor:
            NetworkMonitorToolView(interfaces: interfaces)
        case .uptimeMonitor:
            UptimeToolView(monitor: uptime)
        case .lanScanner:
            LANScannerToolView(model: toolkit.lanScanner)
        case .iperf3:
            Iperf3ToolView(model: toolkit.iperf3)
        case .httpTraffic:
            HTTPTrafficToolView(model: toolkit.httpTraffic)
        case .openConnections, .processTraffic:
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
        }
    }
}
