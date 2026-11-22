import Foundation

enum ToolboxSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case wifi
    case monitoring
    case diagnostics
    case dnsDomains
    case networkTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .wifi: return String(localized: "Wi-Fi")
        case .diagnostics: return String(localized: "Diagnostics")
        case .dnsDomains: return String(localized: "DNS & Domains")
        case .networkTools: return String(localized: "Network Tools")
        case .monitoring: return String(localized: "Monitoring")
        }
    }
}

enum ToolboxTool: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case internetCheck
    case ping
    case traceroute
    case mtr
    case visualTraceroute
    case speedTest

    case dnsLookup
    case dnsPropagation
    case whois
    case geoIP
    case sslCertificate

    case portScan
    case pathCheck
    case subnetCalculator
    case iperf3
    case httpTraffic
    case natTest
    case openConnections
    case processTraffic
    case advancedTools

    case networkMonitor
    case uptimeMonitor
    case routeMonitor
    case lanScanner
    case wifiAnalyzer
    case roamingTest
    case knownNetworks
    case securityWatch
    case clientAnalytics
    case siteSurvey
    case gpsMap

    var id: String { rawValue }

    var title: String { ToolRegistry.descriptor(for: self).title }
    var icon: String { ToolRegistry.descriptor(for: self).icon }
    var section: ToolboxSection { ToolRegistry.descriptor(for: self).section }

    /// Tools that are wired in this build. The rest stay visible with a
    /// "Planned" badge so the sidebar keeps Netutilus's information scent
    /// without pretending the screen works.
    var isAvailable: Bool { ToolRegistry.descriptor(for: self).isAvailable }

    var plannedDetail: String { ToolRegistry.descriptor(for: self).plannedDetail }

    /// False for screens that are a tab of a host tool (see `ToolDescriptor`).
    var showsInSidebar: Bool { ToolRegistry.descriptor(for: self).showsInSidebar }

    /// The view route this tool draws (shared by tabbed tools).
    var screen: ToolScreen { ToolRegistry.descriptor(for: self).screen }

    /// MCP specs this tool's area exposes.
    var mcpTools: [String] { ToolRegistry.descriptor(for: self).mcpTools }
}
