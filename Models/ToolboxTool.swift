import Foundation

enum ToolboxSection: String, CaseIterable, Identifiable, Sendable {
    case wifi
    case monitoring
    case diagnostics
    case dnsDomains
    case networkTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: return String(localized: "Wi-Fi")
        case .diagnostics: return String(localized: "Diagnostics")
        case .dnsDomains: return String(localized: "DNS & Domains")
        case .networkTools: return String(localized: "Network Tools")
        case .monitoring: return String(localized: "Monitoring")
        }
    }
}

enum ToolboxTool: String, CaseIterable, Identifiable, Hashable, Sendable {
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
    case advancedTools

    case networkMonitor
    case uptimeMonitor
    case lanScanner
    case wifiAnalyzer
    case roamingTest
    case knownNetworks
    case siteSurvey

    var id: String { rawValue }

    var title: String { ToolRegistry.descriptor(for: self).title }
    var icon: String { ToolRegistry.descriptor(for: self).icon }
    var section: ToolboxSection { ToolRegistry.descriptor(for: self).section }

    /// Tools that are wired in this build. The rest stay visible with a
    /// "Planned" badge so the sidebar keeps Netutilus's information scent
    /// without pretending the screen works.
    var isAvailable: Bool { ToolRegistry.descriptor(for: self).isAvailable }

    var plannedDetail: String { ToolRegistry.descriptor(for: self).plannedDetail }
}
