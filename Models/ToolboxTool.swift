import Foundation

enum ToolboxSection: String, CaseIterable, Identifiable, Sendable {
    case diagnostics
    case dnsDomains
    case networkTools
    case monitoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diagnostics: return "Diagnostics"
        case .dnsDomains: return "DNS & Domains"
        case .networkTools: return "Network Tools"
        case .monitoring: return "Monitoring"
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
        case .internetCheck: return "Internet Check"
        case .ping: return "Ping"
        case .traceroute: return "Traceroute"
        case .mtr: return "MTR"
        case .speedTest: return "Speed Test"
        case .dnsLookup: return "DNS Lookup"
        case .dnsPropagation: return "DNS Propagation"
        case .whois: return "Whois"
        case .geoIP: return "GeoIP"
        case .sslCertificate: return "SSL Certificate"
        case .portScan: return "Port Scan"
        case .pathCheck: return "Path Check"
        case .subnetCalculator: return "Subnet Calculator"
        case .iperf3: return "iperf3"
        case .networkMonitor: return "Network Monitor"
        case .uptimeMonitor: return "Uptime Monitor"
        case .lanScanner: return "LAN Scanner"
        case .wifiAnalyzer: return "Wi-Fi Analyzer"
        case .wifiNetworks: return "Wi-Fi Networks"
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
        case .networkMonitor, .uptimeMonitor, .lanScanner, .wifiAnalyzer, .wifiNetworks:
            return .monitoring
        }
    }

    /// Tools that are wired in this build. The rest stay visible with a
    /// "Planned" badge so the sidebar keeps Netutilus's information scent
    /// without pretending the screen works.
    var isAvailable: Bool {
        switch self {
        case .internetCheck, .ping, .traceroute, .speedTest, .dnsLookup, .sslCertificate,
            .portScan, .pathCheck, .subnetCalculator, .networkMonitor, .wifiAnalyzer,
            .wifiNetworks:
            return true
        case .mtr, .dnsPropagation, .whois, .geoIP, .iperf3, .uptimeMonitor, .lanScanner:
            return false
        }
    }

    var plannedDetail: String {
        switch self {
        case .mtr: return "Continuous per-hop loss and jitter."
        case .dnsPropagation: return "Check a record across public resolvers."
        case .whois: return "Domain, IP and AS registration data."
        case .geoIP: return "City, country, provider and AS for an address."
        case .iperf3: return "Throughput against your own iperf3 server."
        case .uptimeMonitor: return "Scheduled checks, alerts and outage history."
        case .lanScanner: return "ARP and Bonjour discovery with vendor, ports and alerts."
        default: return "Planned for a later phase."
        }
    }
}
