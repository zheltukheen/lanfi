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
    @AppStorage("LanFi.toolkit.sidebarWidth") private var storedSidebarWidth: Double = 228
    @State private var sidebarDragOffset: CGFloat = 0

    private var currentSidebarWidth: CGFloat {
        max(180, min(360, CGFloat(storedSidebarWidth) + sidebarDragOffset))
    }

    private var searchResults: [ToolboxTool] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return ToolboxTool.allCases.filter { tool in
            tool.title.localizedCaseInsensitiveContains(query)
                || tool.section.title.localizedCaseInsensitiveContains(query)
                || tool.plannedDetail.localizedCaseInsensitiveContains(query)
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
        .onReceive(NotificationCenter.default.publisher(for: .lanfiShowToolkit)) { note in
            if let raw = note.userInfo?["tool"] as? String,
                let tool = ToolboxTool(rawValue: raw)
            {
                toolkit.select(tool)
            }
        }
        .onAppear {
            #if DEBUG
                ToolkitSnapshot.captureIfRequested(toolkit: toolkit, uptime: uptime)
            #endif
        }
    }

    /// The Wi-Fi workspace brings its own toolbar, so it does not need the
    /// generic tool header above it.
    private var isWorkspaceTool: Bool {
        toolkit.selection == .wifiAnalyzer || toolkit.selection == .wifiNetworks
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(ToolboxSection.allCases) { section in
                            sectionHeader(section.title)
                            ForEach(ToolboxTool.allCases.filter { $0.section == section }) {
                                tool in
                                toolRow(tool)
                            }
                        }
                    } else {
                        sectionHeader(String(localized: "Results"))
                        if searchResults.isEmpty {
                            Text("No tools found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(searchResults) { tool in
                                toolRow(tool)
                            }
                        }
                    }
                }
                .padding(8)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
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
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(
                selected ? .white : (tool.isAvailable ? .primary : .secondary)
            )
            .background(
                selected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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
        case .advancedTools:
            AdvancedToolsToolView()
        case .wifiAnalyzer:
            WiFiAnalyzerToolView()
        case .siteSurvey:
            SurveyView(analyzer: analyzer, survey: survey)
        case .wifiNetworks:
            WiFiAnalyzerToolView()
        }
    }
}
