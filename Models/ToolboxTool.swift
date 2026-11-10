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

    case networkMonitor
    case uptimeMonitor
    case lanScanner
    case wifiAnalyzer
    case wifiNetworks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internetCheck: return String(localized: "Internet Check")
        case .ping: return String(localized: "Ping")
        case .traceroute: return String(localized: "Traceroute")
        case .mtr: return String(localized: "MTR")
        case .speedTest: return String(localized: "Speed Test")
        case .dnsLookup: return String(localized: "DNS Lookup")
        case .dnsPropagation: return String(localized: "DNS Propagation")
        case .whois: return String(localized: "Whois")
        case .geoIP: return String(localized: "GeoIP")
        case .sslCertificate: return String(localized: "SSL Certificate")
        case .portScan: return String(localized: "Port Scan")
        case .pathCheck: return String(localized: "Path Check")
        case .subnetCalculator: return String(localized: "Subnet Calculator")
        case .iperf3: return String(localized: "iperf3")
        case .networkMonitor: return String(localized: "Network Monitor")
        case .uptimeMonitor: return String(localized: "Uptime Monitor")
        case .lanScanner: return String(localized: "LAN Scanner")
        case .wifiAnalyzer: return String(localized: "Wi-Fi Analyzer")
        case .wifiNetworks: return String(localized: "Wi-Fi Networks")
        }
    }

    var icon: String {
        switch self {
        case .internetCheck: return "stethoscope"
        case .ping: return "dot.radiowaves.left.and.right"
        case .traceroute: return "point.3.connected.trianglepath.dotted"
        case .mtr: return "chart.line.uptrend.xyaxis"
        case .speedTest: return "speedometer"
        case .dnsLookup: return "magnifyingglass"
        case .dnsPropagation: return "globe"
        case .whois: return "doc.text.magnifyingglass"
        case .geoIP: return "mappin.and.ellipse"
        case .sslCertificate: return "lock.shield"
        case .portScan: return "square.grid.3x3"
        case .pathCheck: return "arrow.triangle.branch"
        case .subnetCalculator: return "number"
        case .iperf3: return "arrow.up.arrow.down"
        case .networkMonitor: return "waveform.path.ecg"
        case .uptimeMonitor: return "clock.badge.checkmark"
        case .lanScanner: return "desktopcomputer"
        case .wifiAnalyzer: return "wifi"
        case .wifiNetworks: return "wifi.router"
        }
    }

    var section: ToolboxSection {
        switch self {
        case .internetCheck, .ping, .traceroute, .mtr, .speedTest:
            return .diagnostics
        case .dnsLookup, .dnsPropagation, .whois, .geoIP, .sslCertificate:
            return .dnsDomains
        case .portScan, .pathCheck, .subnetCalculator, .iperf3:
            return .networkTools
        case .wifiAnalyzer, .wifiNetworks:
            return .wifi
        case .networkMonitor, .uptimeMonitor, .lanScanner:
            return .monitoring
        }
    }

    /// Tools that are wired in this build. The rest stay visible with a
    /// "Planned" badge so the sidebar keeps Netutilus's information scent
    /// without pretending the screen works.
    var isAvailable: Bool {
        switch self {
        case .internetCheck, .ping, .traceroute, .mtr, .speedTest, .dnsLookup,
            .sslCertificate, .portScan, .pathCheck, .subnetCalculator, .networkMonitor,
            .uptimeMonitor, .lanScanner, .iperf3, .wifiAnalyzer, .wifiNetworks:
            return true
        case .dnsPropagation, .whois, .geoIP:
            return false
        }
    }

    var plannedDetail: String {
        switch self {
        case .mtr: return String(localized: "Continuous per-hop loss and jitter.")
        case .dnsPropagation: return String(localized: "Check a record across public resolvers.")
        case .whois: return String(localized: "Domain, IP and AS registration data.")
        case .geoIP: return String(localized: "City, country, provider and AS for an address.")
        case .iperf3: return String(localized: "Throughput against your own iperf3 server.")
        case .uptimeMonitor: return String(localized: "Scheduled checks, alerts and outage history.")
        case .lanScanner: return String(localized: "ARP and Bonjour discovery with vendor, ports and alerts.")
        default: return String(localized: "Planned for a later phase.")
        }
    }
}
