import Foundation

/// A screen the toolkit can show.
///
/// `ToolboxTool` is the identity users and deep links use; several tools can
/// share one screen (`openConnections` and `processTraffic` are the Sockets and
/// Traffic tabs of Connections). Routing lives here and on `ToolDescriptor`, so
/// the sidebar, deep links, the detail switch and the MCP catalogue all read the
/// same table instead of each keeping its own switch over raw tool ids.
enum ToolScreen: String, CaseIterable, Sendable {
    case overview
    case internetCheck
    case ping
    case visualTraceroute
    case speedTest

    case dnsLookup
    case whoisGeoIP
    case sslCertificate

    case portScan
    case pathCheck
    case subnetCalculator
    case iperf3
    case httpTraffic
    case natTest
    case connections
    case advancedTools

    case networkMonitor
    case uptimeMonitor
    case lanScanner
    case wifiAnalyzer
    case roamingTest
    case knownNetworks
    case securityWatch
    case clientAnalytics
    case siteSurvey
}
