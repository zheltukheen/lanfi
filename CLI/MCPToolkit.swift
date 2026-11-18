import Foundation

// MARK: - Results

struct MCPToolOutcome: Equatable {
    let text: String
    let isError: Bool

    static func ok(_ text: String) -> MCPToolOutcome {
        MCPToolOutcome(text: text, isError: false)
    }

    static func error(_ text: String) -> MCPToolOutcome {
        MCPToolOutcome(text: text, isError: true)
    }

    static func json(_ object: [String: Any]) -> MCPToolOutcome {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else { return .error("Could not encode the result as JSON.") }
        return .ok(text)
    }
}

// MARK: - Catalogue

/// Every MCP tool the CLI exposes. Scan tools read the live snapshot the app
/// writes; probe tools run directly on this Mac, just like the toolkit screens.
enum MCPToolkit {
    static var definitions: [[String: Any]] {
        MCPToolRegistry.definitions
    }

    static func call(_ name: String, arguments: [String: Any]) async -> MCPToolOutcome? {
        switch name {
        // Scan analysis (live snapshot or exported JSON)
        case "lanfi_scan_summary": return scanSummary(arguments)
        case "lanfi_analyze": return analyze(arguments)
        case "lanfi_protocols": return protocols(arguments)
        case "lanfi_channels": return channels(arguments)
        case "lanfi_capture": return capture(arguments)
        case "lanfi_har": return har(arguments)
        case "lanfi_spectrum": return spectrum(arguments)
        case "lanfi_devices": return devices(arguments)
        case "lanfi_client_analytics": return clientAnalytics(arguments)
        case "lanfi_survey_plan": return surveyPlan(arguments)
        // Network probes
        case "lanfi_ping": return await ping(arguments)
        case "lanfi_traceroute": return await traceroute(arguments)
        case "lanfi_mtr": return await mtr(arguments)
        case "lanfi_port_scan": return await portScan(arguments)
        case "lanfi_path_check": return await pathCheck(arguments)
        case "lanfi_dns": return await dnsLookup(arguments)
        case "lanfi_dns_propagation": return await dnsPropagation(arguments)
        case "lanfi_whois": return await whois(arguments)
        case "lanfi_geoip": return await geoIP(arguments)
        case "lanfi_tls": return await tls(arguments)
        case "lanfi_subnet": return subnet(arguments)
        case "lanfi_interfaces": return interfaces()
        case "lanfi_routes": return await routes()
        case "lanfi_lan_scan": return await lanScan(arguments)
        case "lanfi_iperf3": return await iperf3(arguments)
        case "lanfi_speed_test": return await speedTest(arguments)
        case "lanfi_open_connections": return await openConnections(arguments)
        case "lanfi_uptime": return uptime()
        case "lanfi_diagnostics": return diagnostics()
        case "lanfi_info": return info()
        default: return nil
        }
    }
}
