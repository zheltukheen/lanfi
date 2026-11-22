import Foundation

/// One place for the static metadata every tool needs.
///
/// The view routing and MCP catalogue are deliberately separate for now; this
/// removes the five parallel switches that made adding a tool touch so many
/// files. The `every tool has a descriptor` test keeps the table exhaustive.
struct ToolDescriptor: Identifiable, Sendable {
    var id: String { tool.rawValue }

    let tool: ToolboxTool
    let title: String
    let icon: String
    let section: ToolboxSection
    let isAvailable: Bool
    let plannedDetail: String
    /// A screen that lives as a tab inside another tool: deep links still
    /// resolve it, but the sidebar lists the host once.
    let showsInSidebar: Bool
    /// The view route this tool draws.
    let screen: ToolScreen
    /// MCP specs (`MCPToolRegistry`) exposed by this tool's area.
    let mcpTools: [String]

    init(
        tool: ToolboxTool, screen: ToolScreen, mcpTools: [String] = [],
        title: String, icon: String, section: ToolboxSection,
        isAvailable: Bool = true,
        plannedDetail: String = String(localized: "Planned for a later phase."),
        showsInSidebar: Bool = true
    ) {
        self.tool = tool
        self.title = title
        self.icon = icon
        self.section = section
        self.isAvailable = isAvailable
        self.plannedDetail = plannedDetail
        self.showsInSidebar = showsInSidebar
        self.screen = screen
        self.mcpTools = mcpTools
    }
}

enum ToolRegistry {
    static let all: [ToolDescriptor] = [
        ToolDescriptor(
            tool: .overview, screen: .overview, title: String(localized: "Overview"),
            icon: "square.grid.2x2", section: .overview,
            plannedDetail: String(localized: "Everything LanFi watches, at a glance.")),
        ToolDescriptor(
            tool: .internetCheck, screen: .internetCheck, mcpTools: ["lanfi_diagnostics"],
            title: String(localized: "Internet Check"),
            icon: "stethoscope", section: .diagnostics),
        ToolDescriptor(
            tool: .ping, screen: .ping, mcpTools: ["lanfi_ping"], title: String(localized: "Ping"),
            icon: "dot.radiowaves.left.and.right", section: .diagnostics),
        ToolDescriptor(
            tool: .traceroute, screen: .visualTraceroute, mcpTools: ["lanfi_traceroute"],
            title: String(localized: "Traceroute"),
            icon: "point.3.connected.trianglepath.dotted", section: .diagnostics,
            plannedDetail: String(localized: "The same screen as Visual Traceroute."),
            // Merged into Visual Traceroute: the map plus the sortable hop table.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .mtr, screen: .visualTraceroute, mcpTools: ["lanfi_mtr"],
            title: String(localized: "MTR"),
            icon: "chart.line.uptrend.xyaxis", section: .diagnostics,
            plannedDetail: String(localized: "Continuous per-hop loss and jitter."),
            // The Continuous tab of the merged Traceroute screen.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .visualTraceroute, screen: .visualTraceroute, title: String(localized: "Visual Traceroute"),
            icon: "map", section: .diagnostics),
        ToolDescriptor(
            tool: .speedTest, screen: .speedTest, mcpTools: ["lanfi_speed_test"],
            title: String(localized: "Speed Test"),
            icon: "speedometer", section: .diagnostics),
        ToolDescriptor(
            tool: .dnsLookup, screen: .dnsLookup, mcpTools: ["lanfi_dns"], title: String(localized: "DNS Lookup"),
            icon: "magnifyingglass", section: .dnsDomains),
        ToolDescriptor(
            tool: .dnsPropagation, screen: .dnsLookup, mcpTools: ["lanfi_dns_propagation"],
            title: String(localized: "DNS Propagation"),
            icon: "globe", section: .dnsDomains,
            plannedDetail: String(localized: "Check a record across public resolvers."),
            // Rendered as the Propagation tab of the DNS tool.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .whois, screen: .whoisGeoIP, mcpTools: ["lanfi_whois"],
            title: String(localized: "Whois & GeoIP"),
            icon: "globe", section: .dnsDomains,
            plannedDetail: String(localized: "Domain, IP and AS registration data.")),
        ToolDescriptor(
            tool: .geoIP, screen: .whoisGeoIP, mcpTools: ["lanfi_geoip"],
            title: String(localized: "GeoIP"),
            icon: "mappin.and.ellipse", section: .dnsDomains,
            plannedDetail: String(localized: "City, country, provider and AS for an address."),
            // The GeoIP tab of the Whois screen.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .sslCertificate, screen: .sslCertificate, mcpTools: ["lanfi_tls"],
            title: String(localized: "SSL Certificate"),
            icon: "lock.shield", section: .dnsDomains),
        ToolDescriptor(
            tool: .portScan, screen: .portScan, mcpTools: ["lanfi_port_scan"], title: String(localized: "Port Scan"),
            icon: "square.grid.3x3", section: .networkTools),
        ToolDescriptor(
            tool: .natTest, screen: .natTest, title: String(localized: "NAT Test"),
            icon: "network", section: .networkTools,
            plannedDetail: String(localized: "What the router does to this Mac's UDP traffic.")),
        ToolDescriptor(
            tool: .pathCheck, screen: .pathCheck, mcpTools: ["lanfi_path_check"],
            title: String(localized: "Path Check"),
            icon: "arrow.triangle.branch", section: .networkTools),
        ToolDescriptor(
            tool: .subnetCalculator, screen: .subnetCalculator, mcpTools: ["lanfi_subnet"],
            title: String(localized: "Subnet Calculator"),
            icon: "number", section: .networkTools),
        ToolDescriptor(
            tool: .iperf3, screen: .iperf3, mcpTools: ["lanfi_iperf3"], title: String(localized: "iperf3"),
            icon: "arrow.up.arrow.down", section: .networkTools,
            plannedDetail: String(localized: "Throughput against your own iperf3 server.")),
        ToolDescriptor(
            tool: .httpTraffic, screen: .httpTraffic, mcpTools: ["lanfi_har"], title: String(localized: "HTTP Traffic"),
            icon: "list.bullet.rectangle.portrait", section: .networkTools),
        ToolDescriptor(
            tool: .openConnections, screen: .connections, mcpTools: ["lanfi_open_connections"],
            title: String(localized: "Connections"),
            icon: "arrow.triangle.branch", section: .monitoring,
            plannedDetail: String(localized: "TCP connections and the processes that own them.")),
        ToolDescriptor(
            tool: .processTraffic, screen: .connections, title: String(localized: "Connections"),
            icon: "arrow.up.arrow.down.circle", section: .monitoring,
            plannedDetail: String(localized: "Per-process receive and send rates from nettop."),
            // Rendered as the Traffic tab of the Connections tool.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .advancedTools, screen: .advancedTools, title: String(localized: "Advanced Tools"),
            icon: "terminal", section: .networkTools),
        ToolDescriptor(
            tool: .networkMonitor, screen: .networkMonitor, mcpTools: ["lanfi_interfaces", "lanfi_routes"],
            title: String(localized: "Network Monitor"),
            icon: "waveform.path.ecg", section: .monitoring),
        ToolDescriptor(
            tool: .uptimeMonitor, screen: .uptimeMonitor, mcpTools: ["lanfi_uptime"],
            title: String(localized: "Uptime Monitor"),
            icon: "clock.badge.checkmark", section: .monitoring,
            plannedDetail: String(localized: "Scheduled checks, alerts and outage history.")),
        ToolDescriptor(
            tool: .routeMonitor, screen: .routeMonitor,
            title: String(localized: "Route Monitor"),
            icon: "square.grid.3x3.middle.filled", section: .monitoring,
            plannedDetail: String(
                localized: "Per-hop latency and loss over time, with route-change events.")),
        ToolDescriptor(
            tool: .lanScanner, screen: .lanScanner, mcpTools: ["lanfi_devices", "lanfi_lan_scan"],
            title: String(localized: "LAN Scanner"),
            icon: "desktopcomputer", section: .monitoring,
            plannedDetail: String(localized: "ARP and Bonjour discovery with vendor, ports and alerts.")),
        ToolDescriptor(
            tool: .wifiAnalyzer, screen: .wifiAnalyzer,
            mcpTools: [
                "lanfi_scan_summary", "lanfi_analyze", "lanfi_protocols", "lanfi_channels", "lanfi_capture",
                "lanfi_spectrum",
            ], title: String(localized: "Wi-Fi Analyzer"),
            icon: "wifi", section: .wifi),
        ToolDescriptor(
            tool: .roamingTest, screen: .roamingTest, title: String(localized: "Roaming Test"),
            icon: "arrow.triangle.2.circlepath", section: .wifi),
        ToolDescriptor(
            tool: .knownNetworks, screen: .knownNetworks, title: String(localized: "Known Networks"),
            icon: "wifi.router", section: .wifi),
        ToolDescriptor(
            tool: .securityWatch, screen: .securityWatch, title: String(localized: "Security Watch"),
            icon: "shield.lefthalf.filled", section: .wifi),
        ToolDescriptor(
            tool: .clientAnalytics, screen: .clientAnalytics, mcpTools: ["lanfi_client_analytics"],
            title: String(localized: "Client Analytics"),
            icon: "person.3", section: .wifi,
            plannedDetail: String(localized: "Per-AP client load, captured clients and probe patterns.")),
        ToolDescriptor(
            tool: .siteSurvey, screen: .siteSurvey, mcpTools: ["lanfi_survey_plan"],
            title: String(localized: "Site Survey"),
            icon: "map", section: .wifi),
        ToolDescriptor(
            tool: .gpsMap, screen: .gpsMap, title: String(localized: "GPS Map"),
            icon: "location.viewfinder", section: .wifi,
            plannedDetail: String(
                localized: "Pin scanned networks on a map and save walks as named trips.")),
    ]

    private static let byTool = Dictionary(
        uniqueKeysWithValues: all.map { ($0.tool, $0) })

    static func descriptor(for tool: ToolboxTool) -> ToolDescriptor {
        guard let descriptor = byTool[tool] else {
            preconditionFailure("Missing ToolDescriptor for \(tool.rawValue)")
        }
        return descriptor
    }
}
