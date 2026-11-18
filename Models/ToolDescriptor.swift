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

    init(
        tool: ToolboxTool, title: String, icon: String, section: ToolboxSection,
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
    }
}

enum ToolRegistry {
    static let all: [ToolDescriptor] = [
        ToolDescriptor(
            tool: .internetCheck, title: String(localized: "Internet Check"),
            icon: "stethoscope", section: .diagnostics),
        ToolDescriptor(
            tool: .ping, title: String(localized: "Ping"),
            icon: "dot.radiowaves.left.and.right", section: .diagnostics),
        ToolDescriptor(
            tool: .traceroute, title: String(localized: "Traceroute"),
            icon: "point.3.connected.trianglepath.dotted", section: .diagnostics),
        ToolDescriptor(
            tool: .mtr, title: String(localized: "MTR"),
            icon: "chart.line.uptrend.xyaxis", section: .diagnostics,
            plannedDetail: String(localized: "Continuous per-hop loss and jitter.")),
        ToolDescriptor(
            tool: .visualTraceroute, title: String(localized: "Visual Traceroute"),
            icon: "map", section: .diagnostics),
        ToolDescriptor(
            tool: .speedTest, title: String(localized: "Speed Test"),
            icon: "speedometer", section: .diagnostics),
        ToolDescriptor(
            tool: .dnsLookup, title: String(localized: "DNS Lookup"),
            icon: "magnifyingglass", section: .dnsDomains),
        ToolDescriptor(
            tool: .dnsPropagation, title: String(localized: "DNS Propagation"),
            icon: "globe", section: .dnsDomains,
            plannedDetail: String(localized: "Check a record across public resolvers.")),
        ToolDescriptor(
            tool: .whois, title: String(localized: "Whois"),
            icon: "doc.text.magnifyingglass", section: .dnsDomains,
            plannedDetail: String(localized: "Domain, IP and AS registration data.")),
        ToolDescriptor(
            tool: .geoIP, title: String(localized: "GeoIP"),
            icon: "mappin.and.ellipse", section: .dnsDomains,
            plannedDetail: String(localized: "City, country, provider and AS for an address.")),
        ToolDescriptor(
            tool: .sslCertificate, title: String(localized: "SSL Certificate"),
            icon: "lock.shield", section: .dnsDomains),
        ToolDescriptor(
            tool: .portScan, title: String(localized: "Port Scan"),
            icon: "square.grid.3x3", section: .networkTools),
        ToolDescriptor(
            tool: .pathCheck, title: String(localized: "Path Check"),
            icon: "arrow.triangle.branch", section: .networkTools),
        ToolDescriptor(
            tool: .subnetCalculator, title: String(localized: "Subnet Calculator"),
            icon: "number", section: .networkTools),
        ToolDescriptor(
            tool: .iperf3, title: String(localized: "iperf3"),
            icon: "arrow.up.arrow.down", section: .networkTools,
            plannedDetail: String(localized: "Throughput against your own iperf3 server.")),
        ToolDescriptor(
            tool: .httpTraffic, title: String(localized: "HTTP Traffic"),
            icon: "list.bullet.rectangle.portrait", section: .networkTools),
        ToolDescriptor(
            tool: .openConnections, title: String(localized: "Connections"),
            icon: "arrow.triangle.branch", section: .monitoring,
            plannedDetail: String(localized: "TCP connections and the processes that own them.")),
        ToolDescriptor(
            tool: .processTraffic, title: String(localized: "Connections"),
            icon: "arrow.up.arrow.down.circle", section: .monitoring,
            plannedDetail: String(localized: "Per-process receive and send rates from nettop."),
            // Rendered as the Traffic tab of the Connections tool.
            showsInSidebar: false),
        ToolDescriptor(
            tool: .advancedTools, title: String(localized: "Advanced Tools"),
            icon: "terminal", section: .networkTools),
        ToolDescriptor(
            tool: .networkMonitor, title: String(localized: "Network Monitor"),
            icon: "waveform.path.ecg", section: .monitoring),
        ToolDescriptor(
            tool: .uptimeMonitor, title: String(localized: "Uptime Monitor"),
            icon: "clock.badge.checkmark", section: .monitoring,
            plannedDetail: String(localized: "Scheduled checks, alerts and outage history.")),
        ToolDescriptor(
            tool: .lanScanner, title: String(localized: "LAN Scanner"),
            icon: "desktopcomputer", section: .monitoring,
            plannedDetail: String(localized: "ARP and Bonjour discovery with vendor, ports and alerts.")),
        ToolDescriptor(
            tool: .wifiAnalyzer, title: String(localized: "Wi-Fi Analyzer"),
            icon: "wifi", section: .wifi),
        ToolDescriptor(
            tool: .roamingTest, title: String(localized: "Roaming Test"),
            icon: "arrow.triangle.2.circlepath", section: .wifi),
        ToolDescriptor(
            tool: .knownNetworks, title: String(localized: "Known Networks"),
            icon: "wifi.router", section: .wifi),
        ToolDescriptor(
            tool: .securityWatch, title: String(localized: "Security Watch"),
            icon: "shield.lefthalf.filled", section: .wifi),
        ToolDescriptor(
            tool: .clientAnalytics, title: String(localized: "Client Analytics"),
            icon: "person.3", section: .wifi,
            plannedDetail: String(localized: "Per-AP client load, captured clients and probe patterns.")),
        ToolDescriptor(
            tool: .siteSurvey, title: String(localized: "Site Survey"),
            icon: "map", section: .wifi),
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
