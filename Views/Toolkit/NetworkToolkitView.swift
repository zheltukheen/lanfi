import SwiftUI

struct NetworkToolkitView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    @EnvironmentObject private var diagnostics: DiagnosticsViewModel
    @EnvironmentObject private var interfaces: InterfacesViewModel
    @EnvironmentObject private var uptime: UptimeMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ToolboxSection.allCases) { section in
                    Text(section.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 10)
                        .padding(.top, section == .diagnostics ? 6 : 16)
                        .padding(.bottom, 4)

                    ForEach(ToolboxTool.allCases.filter { $0.section == section }) { tool in
                        toolRow(tool)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: 228)
        .background(Color(nsColor: .windowBackgroundColor))
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

    @ViewBuilder
    private var detail: some View {
        switch toolkit.selection {
        case .internetCheck:
            InternetCheckToolView(diagnostics: diagnostics)
        case .ping:
            PingToolView(model: toolkit.ping)
        case .traceroute:
            TracerouteToolView(model: toolkit.traceroute)
        case .mtr:
            MTRToolView(model: toolkit.mtr)
        case .speedTest:
            SpeedTestToolView(model: toolkit.speedTest)
        case .dnsLookup:
            DNSToolView(model: toolkit.dns)
        case .sslCertificate:
            SSLToolView(model: toolkit.ssl)
        case .portScan:
            PortScanToolView(model: toolkit.portScan)
        case .pathCheck:
            PathCheckToolView(model: toolkit.pathCheck)
        case .subnetCalculator:
            SubnetToolView(model: toolkit.subnet)
        case .networkMonitor:
            InterfacesView(interfaces: interfaces)
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
        case .wifiNetworks:
            WiFiRedirectToolView(tool: toolkit.selection)
        case .dnsPropagation, .whois, .geoIP:
            ComingSoonToolView(tool: toolkit.selection)
        }
    }
}
