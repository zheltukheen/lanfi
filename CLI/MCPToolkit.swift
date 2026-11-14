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
        scanTools + deviceTools + probeTools + infoTools
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
        case "lanfi_uptime": return uptime()
        case "lanfi_diagnostics": return diagnostics()
        case "lanfi_info": return info()
        default: return nil
        }
    }

    // MARK: - Definitions

    private static var scanTools: [[String: Any]] {
        [
            tool(
                "lanfi_scan_summary",
                "Summarise the networks in the latest live scan (or an exported scan JSON): SSID, BSSID, band, channel, signal and security.",
                properties: ["path": pathProperty]),
            tool(
                "lanfi_analyze",
                "Full analysis: quality score and grade per network, issues, channel recommendations per band and security findings.",
                properties: ["path": pathProperty]),
            tool(
                "lanfi_protocols",
                "Protocol profile per network: radio, EHT/MLO, security, spectrum, mobility, format and vendor blocks with warnings.",
                properties: [
                    "path": pathProperty,
                    "ssid": ["type": "string", "description": "Only this SSID."],
                    "bssid": ["type": "string", "description": "Only this BSSID."],
                ]),
            tool(
                "lanfi_channels",
                "Channel occupancy and ranked recommendations for 2.4, 5 and 6 GHz, including overlap, co-channel counts and DFS notes.",
                properties: ["path": pathProperty]),
            tool(
                "lanfi_capture",
                "Parse a pcap/pcapng capture exported by LanFi: beacons, BSSIDs, channels, RSSI and assembled Multi-Link Operation groups.",
                properties: ["path": ["type": "string", "description": "Capture file path."]],
                required: ["path"]),
            tool(
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
            tool(
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

    private static var deviceTools: [[String: Any]] {
        [
            tool(
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

    private static var probeTools: [[String: Any]] {
        let host = ["type": "string", "description": "Host name or IP address."]
        return [
            tool(
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
            tool(
                "lanfi_traceroute",
                "Traceroute using the system traceroute binary, with per-hop addresses and timings.",
                properties: [
                    "host": host,
                    "maxHops": ["type": "integer", "description": "Default 20."],
                    "waitSeconds": ["type": "integer", "description": "Default 2."],
                    "resolveNames": ["type": "boolean", "description": "Reverse DNS each hop."],
                ],
                required: ["host"]),
            tool(
                "lanfi_mtr",
                "Multi-round per-hop loss and jitter (MTR).",
                properties: [
                    "host": host,
                    "rounds": ["type": "integer", "description": "Default 5."],
                    "maxHops": ["type": "integer", "description": "Default 15."],
                ],
                required: ["host"]),
            tool(
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
            tool(
                "lanfi_path_check",
                "TCP reachability of a host on a few ports, with state and response time.",
                properties: [
                    "host": host,
                    "ports": ["type": "string", "description": "Default 80,443."],
                ],
                required: ["host"]),
            tool(
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
            tool(
                "lanfi_dns_propagation",
                "Query the same record against the public resolver set and group the answers.",
                properties: [
                    "name": ["type": "string", "description": "Domain to resolve."],
                    "type": ["type": "string", "description": "Default A."],
                ],
                required: ["name"]),
            tool(
                "lanfi_whois",
                "Domain or IP registration data, including registrar, statuses and nameservers.",
                properties: ["query": ["type": "string", "description": "Domain or IP."]],
                required: ["query"]),
            tool(
                "lanfi_geoip",
                "City, country, ASN and provider for an address, or for this Mac's public address.",
                properties: ["query": ["type": "string", "description": "Optional IP address."]]),
            tool(
                "lanfi_tls",
                "TLS certificate chain, trust and expiry for a host:port.",
                properties: [
                    "host": host,
                    "port": ["type": "integer", "description": "Default 443."],
                ],
                required: ["host"]),
            tool(
                "lanfi_subnet",
                "IPv4 subnet calculator: network, broadcast, mask, host range and usable count.",
                properties: [
                    "input": [
                        "type": "string",
                        "description": "CIDR like 192.168.1.0/24 or an address plus mask.",
                    ]
                ],
                required: ["input"]),
            tool(
                "lanfi_interfaces",
                "This Mac's interfaces: addresses, primary route, DNS and Wi-Fi link details.",
                properties: [:]),
            tool(
                "lanfi_routes",
                "The IPv4 routing table (netstat -rn -f inet).",
                properties: [:]),
            tool(
                "lanfi_lan_scan",
                "ARP, Bonjour and TCP sweep of the local subnet: devices, vendors, open ports.",
                properties: [
                    "ports": ["type": "string", "description": "Ports to probe, default 22,80,443."]
                ]),
            tool(
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
            tool(
                "lanfi_speed_test",
                "Apple networkQuality throughput, latency and bufferbloat grade.",
                properties: [
                    "timeout": ["type": "integer", "description": "Seconds (5-60, default 20)."]
                ]),
            tool(
                "lanfi_uptime",
                "Uptime Monitor targets and their last checks from ~/Library/Application Support/LanFi/uptime.json.",
                properties: [:]),
            tool(
                "lanfi_diagnostics",
                "The most recent Internet Check report from the app's diagnostics history.",
                properties: [:]),
        ]
    }

    private static var infoTools: [[String: Any]] {
        [
            tool(
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

    // MARK: - Argument helpers

    private static let assetDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func string(_ arguments: [String: Any], _ key: String) -> String? {
        guard let value = arguments[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int(_ arguments: [String: Any], _ key: String) -> Int? {
        if let value = arguments[key] as? Int { return value }
        if let value = arguments[key] as? Double { return Int(value) }
        if let value = arguments[key] as? NSNumber { return value.intValue }
        if let value = arguments[key] as? String { return Int(value) }
        return nil
    }

    private static func double(_ arguments: [String: Any], _ key: String) -> Double? {
        if let value = arguments[key] as? Double { return value }
        if let value = arguments[key] as? Int { return Double(value) }
        if let value = arguments[key] as? NSNumber { return value.doubleValue }
        if let value = arguments[key] as? String { return Double(value) }
        return nil
    }

    private static func flag(_ arguments: [String: Any], _ key: String) -> Bool {
        if let value = arguments[key] as? Bool { return value }
        if let value = arguments[key] as? String { return value == "true" || value == "1" }
        return false
    }

    private static func hostArgument(_ arguments: [String: Any]) throws -> String {
        guard let host = string(arguments, "host") else {
            throw MCPToolArgumentError.message("Pass `host`.")
        }
        return host
    }

    private static func ports(_ arguments: [String: Any], fallback: String) -> [UInt16] {
        let spec = string(arguments, "ports") ?? fallback
        return (try? PortSpec.parse(spec)) ?? []
    }

    // MARK: - Scan analysis

    private static func scanSummary(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            return .json(["networks": scan.summaryJSON])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func analyze(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            return .json(scan.analysisPayload)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func protocols(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            let rows = scan.protocolPayload(
                ssid: string(arguments, "ssid"), bssid: string(arguments, "bssid"))
            guard !rows.isEmpty else { return .error("No network matched that selector.") }
            return .json(["networks": rows])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func channels(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            let report = NetworkAnalyzer.analyze(networks: scan.networks)
            let recommendations = WiFiBand.allCases.compactMap {
                band -> [String: Any]? in
                guard let best = report.bestChannel(for: band) else { return nil }
                return [
                    "band": band.label,
                    "channel": best.channel,
                    "widthMHz": best.widthMHz,
                    "score": best.score,
                    "overlappingNetworks": best.overlappingCount,
                    "coChannelNetworks": best.coChannelCount,
                    "dfs": best.isDFS,
                    "rationale": best.rationale,
                ]
            }
            let occupancy = report.occupancy.map {
                [
                    "band": $0.band.label,
                    "channel": $0.channel,
                    "networks": $0.networkCount,
                    "strongestDbm": $0.strongestRSSI,
                    "averageDbm": $0.averageRSSI,
                ] as [String: Any]
            }
            return .json(["recommendations": recommendations, "occupancy": occupancy])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func capture(_ arguments: [String: Any]) -> MCPToolOutcome {
        guard let path = string(arguments, "path") else {
            return .error("Pass the capture file path as `path`.")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .error("File not found: \(path)")
        }
        do {
            let summary = try PcapAnalyzer.summary(data: Data(contentsOf: url))
            let beacons = summary.beacons
            let groups = MLOGroupAssembler.assemble(beacons: beacons)
            let rows = beacons.map {
                [
                    "ssid": $0.ssid,
                    "bssid": $0.bssid,
                    "channel": $0.channel.map { $0 as Any } ?? NSNull(),
                    "rssi": $0.rssi.map { $0 as Any } ?? NSNull(),
                    "security": $0.security,
                ] as [String: Any]
            }
            let mlo = groups.map { group in
                [
                    "apMLD": group.apMLD,
                    "ssid": group.ssid,
                    "links": group.links.map { link in
                        [
                            "linkID": link.linkID as Any,
                            "bssid": link.bssid as Any,
                            "channel": link.channel as Any,
                            "rssi": link.rssi as Any,
                            "seenInCapture": link.seenInCapture,
                        ] as [String: Any]
                    },
                ] as [String: Any]
            }
            let security: [String: Any] = [
                "handshakes": summary.security.handshakes.map { handshake in
                    [
                        "bssid": handshake.bssid,
                        "keyFrames": handshake.keyFrameCount,
                        "messages": handshake.messageLabel,
                        "complete": handshake.hasCompleteHandshake,
                        "pmkid": handshake.hasPMKID,
                    ] as [String: Any]
                },
                "management": summary.security.management.map { counters in
                    [
                        "bssid": counters.bssid,
                        "beacons": counters.beacons,
                        "probeResponses": counters.probeResponses,
                        "deauth": counters.deauth,
                        "disassoc": counters.disassoc,
                        "burst": counters.burst,
                    ] as [String: Any]
                },
                "findings": summary.security.findings.map { finding in
                    [
                        "id": finding.id,
                        "severity": finding.severity.title,
                        "title": finding.title,
                        "detail": finding.detail,
                    ] as [String: Any]
                },
            ]
            return .json(["networks": rows, "mloGroups": mlo, "security": security])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func har(_ arguments: [String: Any]) -> MCPToolOutcome {
        guard let path = string(arguments, "path") else {
            return .error("Pass the HAR file path as `path`.")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .error("File not found: \(path)")
        }
        let redact = (arguments["redact"] as? Bool) ?? true
        let limit = min(max(int(arguments, "limit") ?? 50, 1), 500)
        do {
            let traffic = try HARParser.parse(data: Data(contentsOf: url))
            let insights = HARTrafficAnalyzer.insights(for: traffic)
            let requests = traffic.entries.prefix(limit).map { entry -> [String: Any] in
                [
                    "method": entry.request.method,
                    "status": entry.response.status,
                    "url": redact ? HARRedaction.url(entry.request.url) : entry.request.url,
                    "mimeType": entry.response.mimeType,
                    "transferBytes": entry.sizeBytes,
                    "timeMs": entry.duration,
                    "cached": entry.isFromCache,
                ]
            }
            let slowest = insights.slowest.map { entry -> [String: Any] in
                [
                    "method": entry.request.method,
                    "status": entry.response.status,
                    "url": redact ? HARRedaction.url(entry.request.url) : entry.request.url,
                    "timeMs": entry.duration,
                ]
            }
            let hosts = insights.hosts.prefix(25).map { host -> [String: Any] in
                [
                    "host": host.host, "requests": host.requests, "failures": host.failures,
                    "bytes": host.bytes, "averageMs": host.averageMilliseconds,
                    "slowestMs": host.slowestMilliseconds,
                ]
            }
            let summary: [String: Any] = [
                "requests": insights.requestCount,
                "failures": insights.failureCount,
                "redirects": insights.redirectCount,
                "cached": insights.cachedCount,
                "transferBytes": insights.transferBytes,
                "contentBytes": insights.contentBytes,
                "averageMs": insights.averageMilliseconds,
                "p95Ms": insights.p95Milliseconds,
                "slowestPhase": insights.slowestPhase?.name ?? NSNull(),
                "creator": traffic.creator ?? NSNull(),
                "redacted": redact,
            ]
            return .json([
                "summary": summary, "requests": requests, "slowest": slowest, "hosts": hosts,
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func spectrum(_ arguments: [String: Any]) -> MCPToolOutcome {
        guard let path = string(arguments, "path") else {
            return .error("Pass the spectrum CSV path as `path`.")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .error("File not found: \(path)")
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .error("Could not read \(path) as UTF-8 text.")
        }
        guard let sweep = SpectrumCSVImporter.parse(text, source: url.lastPathComponent),
            sweep.pointCount >= 2
        else {
            return .error(
                "No frequency/amplitude rows found. Expected two columns: frequency MHz and dBm.")
        }

        func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

        let sorted = sweep.amplitudes.sorted()
        func percentile(_ fraction: Double) -> Double {
            let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
            return round1(sorted[index])
        }
        func share(above threshold: Double) -> Double {
            let count = sweep.amplitudes.filter { $0 >= threshold }.count
            return round1(Double(count) / Double(sweep.pointCount) * 100)
        }

        let ranges: [(String, ClosedRange<Double>)] = [
            ("2.4 GHz", 2400...2483.5),
            ("5 GHz", 5150...5895),
            ("6 GHz", 5925...7125),
        ]
        var bands: [[String: Any]] = []
        for (name, range) in ranges {
            var peak: (mhz: Double, dbm: Double)?
            var sum = 0.0
            var samples = 0
            for (index, dbm) in sweep.amplitudes.enumerated() {
                let mhz = sweep.frequencyMHz(at: index)
                guard range.contains(mhz) else { continue }
                samples += 1
                sum += dbm
                if peak == nil || dbm > peak!.dbm { peak = (mhz, dbm) }
            }
            guard let bandPeak = peak else { continue }
            bands.append([
                "band": name,
                "samples": samples,
                "peakMHz": round1(bandPeak.mhz),
                "peakDbm": round1(bandPeak.dbm),
                "averageDbm": round1(sum / Double(samples)),
            ])
        }

        var payload: [String: Any] = [
            "source": sweep.source,
            "pointCount": sweep.pointCount,
            "startMHz": round1(sweep.startMHz),
            "endMHz": round1(sweep.endMHz),
            "spanMHz": round1(sweep.spanMHz),
            "stepMHz": (sweep.stepMHz * 1000).rounded() / 1000,
            "noiseFloorDbm": percentile(0.1),
            "medianDbm": percentile(0.5),
            "shareAboveMinus70Percent": share(above: -70),
            "shareAboveMinus60Percent": share(above: -60),
            "shareAboveMinus50Percent": share(above: -50),
            "bands": bands,
        ]
        if let peak = sweep.peak() {
            payload["peak"] = ["mhz": round1(peak.mhz), "dbm": round1(peak.dbm)]
        }
        return .json(payload)
    }

    private static func devices(_ arguments: [String: Any]) -> MCPToolOutcome {
        let directory = string(arguments, "directory").map { URL(fileURLWithPath: $0) }
        let store = DeviceShelfStore(directory: directory)
        var rows = store.load()
        let total = rows.count
        if flag(arguments, "online") { rows = rows.filter(\.isOnline) }
        if flag(arguments, "favourite") { rows = rows.filter(\.isFavourite) }
        if flag(arguments, "risky") { rows = rows.filter(\.hasMeaningfulRisk) }
        if let query = string(arguments, "search")?.lowercased() {
            rows = rows.filter { device in
                [
                    device.displayName, device.hostname ?? "", device.ip, device.mac ?? "",
                    device.vendor ?? "", device.manufacturer ?? "", device.model ?? "",
                    device.role ?? "", device.category.title,
                    device.serviceLabels.joined(separator: " "),
                ].joined(separator: " ").lowercased().contains(query)
            }
        }
        rows = Array(rows.prefix(max(1, min(int(arguments, "limit") ?? 200, 1000))))

        let devices: [[String: Any]] = rows.map { device in
            let findings = device.riskFindings
            var row: [String: Any] = [
                "name": device.displayName,
                "ip": device.ip,
                "online": device.isOnline,
                "favourite": device.isFavourite,
                "category": device.category.rawValue,
                "openPorts": device.openPorts.map(Int.init),
                "riskScore": DeviceRiskCatalog.score(for: findings),
                "checks": device.checks,
                "firstSeen": ISO8601DateFormatter().string(from: device.firstSeen),
                "lastSeen": ISO8601DateFormatter().string(from: device.lastSeen),
            ]
            row["availabilityPercent"] = device.availabilityPercent.map { ($0 * 10).rounded() / 10 }
            if let mac = device.mac { row["mac"] = mac }
            if let vendor = device.vendor { row["vendor"] = vendor }
            if let hostname = device.hostname { row["hostname"] = hostname }
            if let model = device.model { row["model"] = model }
            if let manufacturer = device.manufacturer { row["manufacturer"] = manufacturer }
            if let version = device.version { row["version"] = version }
            if let role = device.role { row["role"] = role }
            if let services = device.services, !services.isEmpty { row["services"] = services }
            if let latency = device.latencyMs { row["latencyMs"] = (latency * 10).rounded() / 10 }
            if let assetTag = device.assetTag { row["assetTag"] = assetTag }
            if let serial = device.serialNumber { row["serialNumber"] = serial }
            if let location = device.location { row["location"] = location }
            if let purchase = device.purchaseDate {
                row["purchaseDate"] = assetDay.string(from: purchase)
            }
            if let end = device.warrantyEnd {
                row["warrantyEnd"] = assetDay.string(from: end)
                row["warrantyStatus"] = device.warranty.title
                row["warrantyAttention"] = device.warranty.needsAttention
            }
            row["findings"] = findings.map { finding in
                [
                    "port": Int(finding.port),
                    "title": finding.title,
                    "severity": name(finding.severity),
                    "advice": finding.advice,
                ] as [String: Any]
            }
            return row
        }

        return .json([
            "shelfPath": store.path,
            "count": total,
            "returned": devices.count,
            "devices": devices,
        ])
    }

    private static func name(_ severity: DeviceRiskFinding.Severity) -> String {
        switch severity {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        case .info: return "info"
        }
    }

    // MARK: - Probes

    private static func ping(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let count = max(1, min(int(arguments, "count") ?? 4, 100))
            let timeout = max(0.2, min(double(arguments, "timeout") ?? 1.5, 10))
            let useTCP = (string(arguments, "transport") ?? "icmp").lowercased() == "tcp"
            let port = UInt16(clamping: max(1, min(int(arguments, "port") ?? 443, 65_535)))
            let probe: any PingProbing =
                useTCP ? TCPPingProbe(port: port) : ICMPPingProbe()
            let service = PingService(probe: probe)
            var samples: [PingSample] = []
            for await sample in service.stream(host: host, count: count, interval: 0.25) {
                samples.append(sample)
            }
            guard !samples.isEmpty else { return .error("No probes were sent.") }
            let stats = PingStatistics(host: host, samples: samples)
            return .json([
                "host": stats.host,
                "transmitted": stats.transmitted,
                "received": stats.received,
                "packetLossPercent": stats.packetLossPercent,
                "minMs": stats.minMilliseconds as Any,
                "averageMs": stats.averageMilliseconds as Any,
                "maxMs": stats.maxMilliseconds as Any,
                "jitterMs": stats.jitterMilliseconds as Any,
                "samples": samples.map {
                    [
                        "sequence": $0.sequence,
                        "ms": $0.rttMilliseconds as Any,
                        "error": $0.error as Any,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func traceroute(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let maxHops = max(1, min(int(arguments, "maxHops") ?? 20, 64))
            let wait = max(1, min(int(arguments, "waitSeconds") ?? 2, 10))
            let report = try await SystemTracerouteRunner().trace(
                host: host, maxHops: maxHops, waitSeconds: wait,
                resolveNames: flag(arguments, "resolveNames"))
            return .json([
                "host": report.host,
                "reachedTarget": report.reachedTarget,
                "hops": report.hops.map {
                    [
                        "ttl": $0.ttl,
                        "address": $0.address as Any,
                        "hostname": $0.hostname as Any,
                        "ms": $0.milliseconds,
                        "timedOut": $0.timedOut,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func mtr(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let rounds = max(1, min(int(arguments, "rounds") ?? 5, 30))
            let hops = max(1, min(int(arguments, "maxHops") ?? 15, 40))
            let report = try await MTRService(runner: SystemTracerouteRunner()).run(
                host: host, rounds: rounds, maxHops: hops, waitSeconds: 1,
                onUpdate: { _ in })
            let hopRows: [[String: Any]] = report.hops.map { hop in
                var row: [String: Any] = [
                    "hop": hop.hop,
                    "sent": hop.sent,
                    "received": hop.received,
                ]
                row["address"] = hop.address as Any
                row["hostname"] = hop.hostname as Any
                row["lossPercent"] =
                    hop.sent == 0
                    ? 0 : Double(hop.sent - hop.received) / Double(hop.sent) * 100
                row["lastMs"] = hop.lastMilliseconds as Any
                row["averageMs"] = hop.averageMilliseconds as Any
                row["jitterMs"] = hop.jitterMilliseconds as Any
                return row
            }
            return .json(["host": report.host, "rounds": report.rounds, "hops": hopRows])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func portScan(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let spec = ports(arguments, fallback: "22,80,443,8080")
            guard !spec.isEmpty else { return .error("No ports to scan.") }
            let timeout = max(0.2, min(double(arguments, "timeout") ?? 1.0, 10))
            let results = await PortScanner(probe: TCPPortProbe()).scan(
                host: host, ports: spec, timeout: timeout, concurrency: 24)
            return .json([
                "host": host,
                "open": results.filter { $0.state == .open }.count,
                "results": results.map {
                    [
                        "port": Int($0.port),
                        "state": $0.state.rawValue,
                        "service": $0.service as Any,
                        "ms": $0.responseMilliseconds as Any,
                        "detail": $0.detail as Any,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func pathCheck(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let spec = ports(arguments, fallback: "80,443")
            guard !spec.isEmpty else { return .error("No ports to check.") }
            let results = await withTaskGroup(of: [String: Any].self) { group in
                for port in spec.prefix(32) {
                    group.addTask {
                        let outcome = await TCPProbe.connect(host: host, port: port, timeout: 4)
                        var row: [String: Any] = ["port": Int(port)]
                        switch outcome {
                        case .open(let milliseconds):
                            row["state"] = "open"
                            row["ms"] = milliseconds
                        case .closed(let milliseconds, let detail):
                            row["state"] = "closed"
                            row["ms"] = milliseconds as Any
                            row["detail"] = detail as Any
                        case .filtered(let detail):
                            row["state"] = "filtered"
                            row["detail"] = detail as Any
                        }
                        return row
                    }
                }
                var rows: [[String: Any]] = []
                for await row in group { rows.append(row) }
                return rows.sorted {
                    ($0["port"] as? Int ?? 0) < ($1["port"] as? Int ?? 0)
                }
            }
            return .json(["host": host, "results": results])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func dnsLookup(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let name = string(arguments, "name") else {
            return .error("Pass a domain as `name`.")
        }
        guard let type = recordType(string(arguments, "type") ?? "A") else {
            return .error("Unsupported record type.")
        }
        let resolverArgument = (string(arguments, "resolver") ?? "system").lowercased()
        let resolver: DNSResolver
        switch resolverArgument {
        case "cloudflare": resolver = .cloudflare
        case "google": resolver = .google
        case "system": resolver = .system
        default:
            guard let custom = DNSResolver.custom(resolverArgument) else {
                return .error("Unsupported resolver: \(resolverArgument).")
            }
            resolver = custom
        }
        do {
            let result = try await UDPDNSClient().lookup(
                host: name, type: type, resolver: resolver, timeout: 6)
            return .json([
                "host": result.host,
                "resolver": result.resolver,
                "milliseconds": result.milliseconds,
                "records": result.records.map(recordJSON),
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func dnsPropagation(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let name = string(arguments, "name") else {
            return .error("Pass a domain as `name`.")
        }
        guard let type = recordType(string(arguments, "type") ?? "A") else {
            return .error("Unsupported record type.")
        }
        let resolvers = DNSResolver.propagation
        let rows = await withTaskGroup(of: [String: Any].self) { group in
            for resolver in resolvers {
                group.addTask {
                    do {
                        let result = try await UDPDNSClient().lookup(
                            host: name, type: type, resolver: resolver, timeout: 5)
                        return [
                            "resolver": resolver.name,
                            "address": resolver.address ?? "system",
                            "ms": result.milliseconds,
                            "records": result.records.map { $0.value },
                            "error": NSNull(),
                        ]
                    } catch {
                        return [
                            "resolver": resolver.name,
                            "address": resolver.address ?? "system",
                            "ms": 0,
                            "records": [String](),
                            "error": error.localizedDescription,
                        ]
                    }
                }
            }
            var values: [[String: Any]] = []
            for await value in group { values.append(value) }
            return values
        }
        return .json(["name": name, "type": type.label, "results": rows])
    }

    private static func whois(_ arguments: [String: Any]) async -> MCPToolOutcome {
        guard let query = string(arguments, "query") else {
            return .error("Pass a domain or IP as `query`.")
        }
        do {
            let report = try await WhoisClient().lookup(query)
            return .json([
                "query": report.query,
                "objectType": report.objectType,
                "name": report.name,
                "handle": report.handle as Any,
                "registrar": report.registrar as Any,
                "statuses": report.statuses,
                "nameservers": report.nameservers,
                "events": report.events.map {
                    [
                        "action": $0.action,
                        "date": $0.date.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func geoIP(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let report = try await GeoIPClient().lookup(string(arguments, "query"))
            return .json([
                "query": report.query,
                "ip": report.ip,
                "type": report.type,
                "country": report.country,
                "countryCode": report.countryCode,
                "region": report.region,
                "city": report.city,
                "latitude": report.latitude,
                "longitude": report.longitude,
                "asn": report.asn as Any,
                "organization": report.organization,
                "isp": report.isp,
                "timezone": report.timezone,
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func tls(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let port = UInt16(clamping: max(1, min(int(arguments, "port") ?? 443, 65_535)))
            let report = try await URLSessionTLSCertificateInspector().inspect(
                host: host, port: port, timeout: 8)
            return .json([
                "host": report.host,
                "port": Int(report.port),
                "trusted": report.trusted,
                "expired": report.expired,
                "expiresSoon": report.expiresSoon,
                "daysRemaining": report.daysRemaining as Any,
                "certificates": report.certificates.map {
                    [
                        "subject": $0.subject,
                        "issuer": $0.issuer,
                        "notBefore": $0.notBefore.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                        "notAfter": $0.notAfter.map {
                            ISO8601DateFormatter().string(from: $0) as Any
                        } ?? NSNull(),
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func subnet(_ arguments: [String: Any]) -> MCPToolOutcome {
        guard let input = string(arguments, "input") else {
            return .error("Pass a CIDR or address plus mask as `input`.")
        }
        guard let info = SubnetCalculator.parse(input) else {
            return .error("Could not parse the IPv4 network.")
        }
        return .json([
            "network": info.network.description,
            "broadcast": info.broadcast.description,
            "netmask": info.netmask.description,
            "prefixLength": info.prefixLength,
            "firstUsable": info.firstUsable?.description as Any,
            "lastUsable": info.lastUsable?.description as Any,
            "totalAddresses": info.totalAddresses,
            "usableHosts": info.usableHosts,
        ])
    }

    private static func interfaces() -> MCPToolOutcome {
        let report = SystemInterfaceScanner.scan()
        return .json([
            "generatedAt": ISO8601DateFormatter().string(from: report.generatedAt),
            "primaryInterface": report.primaryInterface as Any,
            "router": report.router as Any,
            "dnsServers": report.dnsServers,
            "interfaces": report.interfaces.map {
                [
                    "name": $0.bsdName,
                    "displayName": $0.displayName,
                    "kind": $0.kind.rawValue,
                    "up": $0.isUp,
                    "running": $0.isRunning,
                    "primary": $0.isPrimary,
                    "mac": $0.macAddress as Any,
                    "ipv4": $0.ipv4.map(\.address),
                    "ipv6": $0.ipv6.map(\.address),
                    "ssid": $0.ssid as Any,
                    "rssi": $0.rssi as Any,
                    "rxBytes": $0.rxBytes,
                    "txBytes": $0.txBytes,
                ] as [String: Any]
            },
        ])
    }

    private static func routes() async -> MCPToolOutcome {
        do {
            let routes = try await RouteTableReader().read()
            return .json([
                "routes": routes.map {
                    [
                        "destination": $0.destination,
                        "gateway": $0.gateway,
                        "flags": $0.flags,
                        "interface": $0.interface,
                        "isDefault": $0.isDefault,
                    ] as [String: Any]
                }
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func lanScan(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let service = LANScannerService(
                probePorts: ports(arguments, fallback: "22,80,443,445,5000,7000,8080,3389"))
            let result = try await service.scan(knownMACs: [], guardEnabled: false)
            return .json([
                "interface": result.interfaceName,
                "subnet": result.subnet,
                "gateway": result.gateway as Any,
                "devices": result.devices.map {
                    [
                        "ip": $0.ip,
                        "mac": $0.mac as Any,
                        "vendor": $0.vendor as Any,
                        "hostname": $0.hostname as Any,
                        "model": $0.model as Any,
                        "manufacturer": $0.manufacturer as Any,
                        "version": $0.version as Any,
                        "role": $0.deviceType as Any,
                        "services": $0.services,
                        "banners": Dictionary(
                            uniqueKeysWithValues: $0.banners.map { (String($0.key), $0.value) }),
                        "openPorts": $0.openPorts.map(Int.init),
                        "latencyMs": $0.latencyMilliseconds as Any,
                        "isGateway": $0.isGateway,
                        "isThisMac": $0.isThisMac,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func iperf3(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let host = try hostArgument(arguments)
            let port = UInt16(clamping: max(1, min(int(arguments, "port") ?? 5201, 65_535)))
            let duration = max(1, min(int(arguments, "duration") ?? 5, 120))
            let direction =
                Iperf3Direction(rawValue: (string(arguments, "direction") ?? "upload").lowercased())
                ?? .upload
            let report = try await Iperf3Runner().run(
                host: host, port: port, durationSeconds: duration, direction: direction)
            return .json([
                "host": report.host,
                "port": Int(report.port),
                "direction": report.direction.rawValue,
                "headlineMbps": report.headlineMegabitsPerSecond as Any,
                "sentMbps": report.sentMegabitsPerSecond as Any,
                "receivedMbps": report.receivedMegabitsPerSecond as Any,
                "intervals": report.intervals.map {
                    [
                        "start": $0.start,
                        "end": $0.end,
                        "mbps": $0.megabitsPerSecond,
                    ] as [String: Any]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func speedTest(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let timeout = max(5, min(int(arguments, "timeout") ?? 20, 60))
            let report = try await ThroughputTester.run(timeout: timeout)
            return .json([
                "downloadMbps": report.downloadMbps as Any,
                "uploadMbps": report.uploadMbps as Any,
                "latencyMs": report.latencyMilliseconds as Any,
                "responsiveness": report.responsiveness as Any,
                "grade": report.bufferbloatGrade as Any,
                "testedAt": ISO8601DateFormatter().string(from: report.testedAt),
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func uptime() -> MCPToolOutcome {
        let snapshot = UptimeStore().load()
        let checksByTarget = Dictionary(grouping: snapshot.checks, by: \.targetID)
        return .json([
            "targets": snapshot.targets.map { target in
                let checks = checksByTarget[target.id] ?? []
                let up = checks.filter(\.isUp).count
                return [
                    "name": target.name,
                    "address": target.address,
                    "kind": target.kind.rawValue,
                    "enabled": target.enabled,
                    "intervalMinutes": target.intervalMinutes,
                    "checks": checks.count,
                    "upPercent": checks.isEmpty
                        ? NSNull() : Double(up) / Double(checks.count) * 100,
                    "lastCheck": checks.last.map {
                        [
                            "at": ISO8601DateFormatter().string(from: $0.at),
                            "up": $0.isUp,
                            "latencyMs": $0.latencyMilliseconds as Any,
                            "detail": $0.detail as Any,
                        ] as [String: Any]
                    } ?? NSNull(),
                ] as [String: Any]
            }
        ])
    }

    private static func diagnostics() -> MCPToolOutcome {
        guard let report = DiagnosticsHistoryStore().load().last else {
            return .error(
                "No diagnostics report yet. Run Internet Check in LanFi once.")
        }
        return .json([
            "startedAt": ISO8601DateFormatter().string(from: report.startedAt),
            "summary": report.summary,
            "overall": report.overall.rawValue,
            "healthScore": report.healthScore,
            "checks": report.checks.map {
                [
                    "id": $0.id,
                    "title": $0.title,
                    "status": $0.status.rawValue,
                    "value": $0.value,
                    "detail": $0.detail,
                ] as [String: Any]
            },
        ])
    }

    private static func info() -> MCPToolOutcome {
        let url = MCPPaths.liveSnapshotURL
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = attributes?[.modificationDate] as? Date
        return .json([
            "liveSnapshot": url.path,
            "liveSnapshotExists": FileManager.default.fileExists(atPath: url.path),
            "liveSnapshotModified": modified.map {
                ISO8601DateFormatter().string(from: $0) as Any
            } ?? NSNull(),
            "note":
                "Keep LanFi running to refresh the live snapshot. Pass `path` to any scan tool to analyse an exported scan JSON instead.",
        ])
    }

    // MARK: - Shared encoding

    private static func recordType(_ raw: String) -> DNSRecordType? {
        let upper = raw.uppercased()
        return DNSRecordType.allCases.first { $0.label.uppercased() == upper }
    }

    private static func recordJSON(_ record: DNSRecord) -> [String: Any] {
        [
            "type": record.type.label,
            "name": record.name,
            "ttl": record.ttl,
            "priority": record.priority.map { $0 as Any } ?? NSNull(),
            "value": record.value,
        ]
    }
}

enum MCPToolArgumentError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}
