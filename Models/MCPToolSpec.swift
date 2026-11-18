import Foundation

/// One MCP tool the CLI serves: its advertised name, summary and input schema.
///
/// The specs live in this registry rather than inside the CLI handler, so a
/// tool's catalogue entry, view route (`ToolDescriptor.screen`) and MCP surface
/// are described in the same layer and the app, CLI and tests build them from
/// one source. `ToolDescriptor.mcpTools` names the specs a screen exposes; the
/// handler switch in `MCPToolkit.call` maps those names to implementations.
struct MCPToolSpec {
    let name: String
    let summary: String
    let properties: [String: Any]
    let required: [String]

    init(
        _ name: String,
        _ summary: String,
        properties: [String: Any],
        required: [String] = []
    ) {
        self.name = name
        self.summary = summary
        self.properties = properties
        self.required = required
    }

    var definition: [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": summary, "inputSchema": schema]
    }
}

enum MCPToolRegistry {
    // MARK: - Catalogue

    private static var scanTools: [MCPToolSpec] {
        [
            MCPToolSpec(
                "lanfi_scan_summary",
                "Summarise the networks in the latest live scan (or an exported scan JSON): SSID, BSSID, band, channel, signal and security.",
                properties: ["path": pathProperty]),
            MCPToolSpec(
                "lanfi_analyze",
                "Full analysis: quality score and grade per network, issues, channel recommendations per band and security findings.",
                properties: ["path": pathProperty]),
            MCPToolSpec(
                "lanfi_protocols",
                "Protocol profile per network: radio, EHT/MLO, security, spectrum, mobility, format and vendor blocks with warnings.",
                properties: [
                    "path": pathProperty,
                    "ssid": ["type": "string", "description": "Only this SSID."],
                    "bssid": ["type": "string", "description": "Only this BSSID."],
                ]),
            MCPToolSpec(
                "lanfi_channels",
                "Channel occupancy and ranked recommendations for 2.4, 5 and 6 GHz, including overlap, co-channel counts and DFS notes.",
                properties: ["path": pathProperty]),
            MCPToolSpec(
                "lanfi_capture",
                "Parse a pcap/pcapng capture exported by LanFi: beacons, BSSIDs, channels, RSSI and assembled Multi-Link Operation groups.",
                properties: ["path": ["type": "string", "description": "Capture file path."]],
                required: ["path"]),
            MCPToolSpec(
                "lanfi_har",
                "Analyze a HAR archive exported by browser DevTools or a debugging proxy: slowest requests, failures, p95 latency, bytes per host and the dominant timing phase. Credentials are redacted unless `redact` is false.",
                properties: [
                    "path": ["type": "string", "description": "HAR file path."],
                    "redact": [
                        "type": "boolean",
                        "description": "Mask Authorization, cookie and token values. Default true.",
                    ],
                    "limit": ["type": "integer", "description": "Requests to list, default 50, max 500."],
                ],
                required: ["path"]),
            MCPToolSpec(
                "lanfi_client_analytics",
                "Per-access-point advertised client load from the latest scan (or an exported scan JSON): clients, utilization, busiest APs and plain-language insights.",
                properties: ["path": pathProperty]),
            MCPToolSpec(
                "lanfi_spectrum",
                "Analyse a hardware spectrum trace exported as CSV (RF Explorer or Wi-Spy Chanalyzer, one contiguous sweep): span, noise floor, peak, per-band strongest signal and the share of the trace above -70/-60/-50 dBm.",
                properties: [
                    "path": [
                        "type": "string",
                        "description": "CSV path with frequency (MHz), amplitude (dBm) rows.",
                    ]
                ],
                required: ["path"]),
        ]
    }

    private static var deviceTools: [MCPToolSpec] {
        [
            MCPToolSpec(
                "lanfi_devices",
                "Read the Device Shelf: every device the LAN Scanner has inventoried, with name, IP, MAC, vendor, type, online state, open ports, availability, risk findings and score. Filters are optional.",
                properties: [
                    "directory": [
                        "type": "string",
                        "description":
                            "Folder containing device-shelf.json. Omit to use the app's shelf (Application Support/LanFi).",
                    ],
                    "online": ["type": "boolean", "description": "Only devices online now."],
                    "favourite": ["type": "boolean", "description": "Only favourites."],
                    "risky": [
                        "type": "boolean",
                        "description": "Only devices with a medium-or-higher risk finding.",
                    ],
                    "search": [
                        "type": "string",
                        "description": "Match name, hostname, IP, MAC, vendor or type.",
                    ],
                    "limit": ["type": "integer", "description": "Default 200, max 1000."],
                ])
        ]
    }

    private static var probeTools: [MCPToolSpec] {
        let host = ["type": "string", "description": "Host name or IP address."]
        return [
            MCPToolSpec(
                "lanfi_ping",
                "ICMP or TCP ping with loss, jitter and per-probe round-trip times.",
                properties: [
                    "host": host,
                    "count": ["type": "integer", "description": "Probes (1-100, default 4)."],
                    "timeout": ["type": "number", "description": "Seconds per probe (default 1.5)."],
                    "transport": ["type": "string", "description": "icmp or tcp (default icmp)."],
                    "port": ["type": "integer", "description": "TCP port for transport=tcp."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_traceroute",
                "Traceroute using the system traceroute binary, with per-hop addresses and timings.",
                properties: [
                    "host": host,
                    "maxHops": ["type": "integer", "description": "Default 20."],
                    "waitSeconds": ["type": "integer", "description": "Default 2."],
                    "resolveNames": ["type": "boolean", "description": "Reverse DNS each hop."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_mtr",
                "Multi-round per-hop loss and jitter (MTR).",
                properties: [
                    "host": host,
                    "rounds": ["type": "integer", "description": "Default 5."],
                    "maxHops": ["type": "integer", "description": "Default 15."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_port_scan",
                "TCP connect scan of a host and port list (open/closed/filtered).",
                properties: [
                    "host": host,
                    "ports": [
                        "type": "string",
                        "description": "Ports like 22,80,443 or 1-1024. Default 22,80,443,8080.",
                    ],
                    "timeout": ["type": "number", "description": "Seconds per probe (default 1.0)."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_path_check",
                "TCP reachability of a host on a few ports, with state and response time.",
                properties: [
                    "host": host,
                    "ports": ["type": "string", "description": "Default 80,443."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_dns",
                "Resolve a name over UDP against the system, Cloudflare, Google or a custom resolver.",
                properties: [
                    "name": ["type": "string", "description": "Domain to resolve."],
                    "type": [
                        "type": "string",
                        "description": "A, AAAA, CNAME, MX, TXT, NS, SOA, SRV, CAA or PTR.",
                    ],
                    "resolver": [
                        "type": "string",
                        "description": "system, cloudflare, google or an IPv4 address.",
                    ],
                ],
                required: ["name"]),
            MCPToolSpec(
                "lanfi_dns_propagation",
                "Query the same record against the public resolver set and group the answers.",
                properties: [
                    "name": ["type": "string", "description": "Domain to resolve."],
                    "type": ["type": "string", "description": "Default A."],
                ],
                required: ["name"]),
            MCPToolSpec(
                "lanfi_whois",
                "Domain or IP registration data, including registrar, statuses and nameservers.",
                properties: ["query": ["type": "string", "description": "Domain or IP."]],
                required: ["query"]),
            MCPToolSpec(
                "lanfi_geoip",
                "City, country, ASN and provider for an address, or for this Mac's public address.",
                properties: ["query": ["type": "string", "description": "Optional IP address."]]),
            MCPToolSpec(
                "lanfi_tls",
                "TLS certificate chain, trust and expiry for a host:port.",
                properties: [
                    "host": host,
                    "port": ["type": "integer", "description": "Default 443."],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_subnet",
                "IPv4 subnet calculator: network, broadcast, mask, host range and usable count.",
                properties: [
                    "input": [
                        "type": "string",
                        "description": "CIDR like 192.168.1.0/24 or an address plus mask.",
                    ]
                ],
                required: ["input"]),
            MCPToolSpec(
                "lanfi_interfaces",
                "This Mac's interfaces: addresses, primary route, DNS and Wi-Fi link details.",
                properties: [:]),
            MCPToolSpec(
                "lanfi_routes",
                "The IPv4 routing table (netstat -rn -f inet).",
                properties: [:]),
            MCPToolSpec(
                "lanfi_lan_scan",
                "ARP, Bonjour and TCP sweep of the local subnet: devices, vendors, open ports.",
                properties: [
                    "ports": ["type": "string", "description": "Ports to probe, default 22,80,443."]
                ]),
            MCPToolSpec(
                "lanfi_iperf3",
                "Run the iperf3 client against your own server and return the parsed report.",
                properties: [
                    "host": host,
                    "port": ["type": "integer", "description": "Default 5201."],
                    "duration": ["type": "integer", "description": "Seconds (1-120, default 5)."],
                    "direction": [
                        "type": "string",
                        "description": "upload, download or bidirectional (default upload).",
                    ],
                ],
                required: ["host"]),
            MCPToolSpec(
                "lanfi_speed_test",
                "Apple networkQuality throughput, latency and bufferbloat grade.",
                properties: [
                    "timeout": ["type": "integer", "description": "Seconds (5-60, default 20)."]
                ]),
            MCPToolSpec(
                "lanfi_survey_plan",
                "Plan access-point placement for a rectangular floor: free-space radius from tx power and target RSSI, grid AP positions, spacing, estimated coverage and notes.",
                properties: [
                    "widthMeters": ["type": "number", "description": "Default 20."],
                    "heightMeters": ["type": "number", "description": "Default 12."],
                    "targetRSSI": ["type": "integer", "description": "Default -65 dBm."],
                    "txPowerDbm": ["type": "number", "description": "Default 20 dBm."],
                    "band": ["type": "string", "description": "2.4GHz, 5GHz or 6GHz (default 5GHz)."],
                    "channel": ["type": "integer", "description": "Default 36."],
                ]),
            MCPToolSpec(
                "lanfi_open_connections",
                "TCP connections on this Mac from read-only lsof: process, PID, user, protocol, local/remote endpoint and state. Other users' sockets may be hidden without root.",
                properties: [
                    "listeners": [
                        "type": "boolean", "description": "Include listening sockets. Default false.",
                    ],
                    "limit": ["type": "integer", "description": "Default 500, max 2000."],
                ]),
            MCPToolSpec(
                "lanfi_uptime",
                "Uptime Monitor targets and their last checks from ~/Library/Application Support/LanFi/uptime.json.",
                properties: [:]),
            MCPToolSpec(
                "lanfi_diagnostics",
                "The most recent Internet Check report from the app's diagnostics history.",
                properties: [:]),
        ]
    }

    private static var infoTools: [MCPToolSpec] {
        [
            MCPToolSpec(
                "lanfi_info",
                "Where the live snapshot lives, how fresh it is, and how to point LanFi tools at an exported scan.",
                properties: [:])
        ]
    }

    private static func tool(
        _ name: String,
        _ description: String,
        properties: [String: Any],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private static let pathProperty: [String: Any] = [
        "type": "string",
        "description":
            "Scan JSON export path. Omit to use the live snapshot written by the running LanFi app.",
    ]

    static var all: [MCPToolSpec] {
        scanTools + deviceTools + probeTools + infoTools
    }

    static var names: [String] { all.map(\.name) }
    static var definitions: [[String: Any]] { all.map(\.definition) }
}
