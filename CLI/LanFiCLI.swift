import Foundation

@main
struct LanFiCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(2)
        }
        do {
            switch command {
            case "summary":
                try requireFile(arguments, index: 1) { url in
                    let scan = try ScanExport.load(url)
                    if arguments.contains("--json") {
                        printJSON(scan.summaryJSON)
                    } else {
                        print(scan.summaryText)
                    }
                }
            case "protocols":
                try requireFile(arguments, index: 1) { url in
                    let scan = try ScanExport.load(url)
                    for network in scan.networks {
                        let metrics = NetworkAnalyzer.metricsFor(network, among: scan.networks)
                        let profile = ProtocolAnalyzer.profile(for: network, metrics: metrics)
                        print("\(network.displaySSID) · \(network.bssid)")
                        for block in profile.blocks {
                            print("  \(block.title): \(block.facts.prefix(2).map { "\($0.label)=\($0.value)" }.joined(separator: ", "))")
                        }
                    }
                }
            case "pcap":
                try requireFile(arguments, index: 1) { url in
                    let beacons = try PcapAnalyzer.parse(data: Data(contentsOf: url))
                    let mloGroups = MLOGroupAssembler.assemble(beacons: beacons)
                    if arguments.contains("--json") {
                        let rows = beacons.map {
                            [
                                "ssid": $0.ssid, "bssid": $0.bssid,
                                "channel": $0.channel ?? 0, "rssi": $0.rssi ?? 0,
                                "security": $0.security,
                            ] as [String: Any]
                        }
                        let groups = mloGroups.map { group in
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
                                    ]
                                },
                            ]
                        }
                        printJSON(["networks": rows, "mloGroups": groups])
                    } else {
                        for beacon in beacons {
                            print("\(beacon.ssid)\t\(beacon.bssid)\tch \(beacon.channel.map(String.init) ?? "-")\t\(beacon.rssi.map { "\($0) dBm" } ?? "-")\t\(beacon.security)")
                        }
                        for group in mloGroups {
                            let links = group.links.map {
                                "link \($0.linkID.map(String.init) ?? "?"): \($0.bssid ?? "unknown")"
                            }.joined(separator: ", ")
                            print("MLO \(group.apMLD) (\(group.ssid)): \(links)")
                        }
                    }
                }
            case "har":
                try requireFile(arguments, index: 1) { url in
                    let traffic = try HARParser.parse(data: Data(contentsOf: url))
                    let insights = HARTrafficAnalyzer.insights(for: traffic)
                    let redact = !arguments.contains("--no-redact")
                    if arguments.contains("--markdown") {
                        print(
                            HARTrafficAnalyzer.markdownReport(
                                for: traffic, redacted: !arguments.contains("--no-redact")))
                        return
                    }
                    if arguments.contains("--json") {
                        let slowest = insights.slowest.map { entry -> [String: Any] in
                            [
                                "method": entry.request.method,
                                "status": entry.response.status,
                                "url": redact
                                    ? HARRedaction.url(entry.request.url) : entry.request.url,
                                "timeMs": entry.duration,
                            ]
                        }
                        let hosts = insights.hosts.map { host -> [String: Any] in
                            [
                                "host": host.host, "requests": host.requests,
                                "failures": host.failures, "bytes": host.bytes,
                                "averageMs": host.averageMilliseconds,
                            ]
                        }
                        let summary: [String: Any] = [
                            "requests": insights.requestCount,
                            "failures": insights.failureCount,
                            "redirects": insights.redirectCount,
                            "cached": insights.cachedCount,
                            "transferBytes": insights.transferBytes,
                            "averageMs": insights.averageMilliseconds,
                            "p95Ms": insights.p95Milliseconds,
                            "slowestPhase": insights.slowestPhase?.name ?? NSNull(),
                            "creator": traffic.creator ?? NSNull(),
                        ]
                        printJSON(["summary": summary, "slowest": slowest, "hosts": hosts])
                    } else {
                        print(
                            "\(insights.requestCount) requests · \(insights.failureCount) failures · "
                                + "\(HARTrafficAnalyzer.bytes(insights.transferBytes)) · "
                                + "avg \(HAREntry.milliseconds(insights.averageMilliseconds)) · "
                                + "p95 \(HAREntry.milliseconds(insights.p95Milliseconds))"
                        )
                        for entry in insights.slowest {
                            let target = redact
                                ? HARRedaction.url(entry.host + entry.path)
                                : entry.host + entry.path
                            print(
                                "  \(entry.durationLabel)\t\(entry.statusLabel)\t\(entry.request.method)\t\(target)"
                            )
                        }
                        for host in insights.hosts.prefix(10) {
                            print(
                                "  \(host.host)\t\(host.requests) req\t\(HARTrafficAnalyzer.bytes(host.bytes))\tavg \(HAREntry.milliseconds(host.averageMilliseconds))"
                            )
                        }
                    }
                }
            case "mcp":
                MCPServer.run()
            case "help", "--help", "-h":
                printUsage()
            default:
                FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
                printUsage()
                exit(2)
            }
        } catch {
            FileHandle.standardError.write(Data("lanfi-cli: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func requireFile(_ arguments: [String], index: Int, _ work: (URL) throws -> Void) throws {
        guard arguments.indices.contains(index) else {
            throw CLIError.message("Missing file path.")
        }
        let url = URL(fileURLWithPath: arguments[index])
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.message("File not found: \(url.path)")
        }
        try work(url)
    }

    private static func printUsage() {
        print(
            """
            LanFi CLI — offline scan and capture automation

            Usage:
              lanfi-cli summary <scan.json> [--json]
              lanfi-cli protocols <scan.json>
              lanfi-cli pcap <capture.pcap|pcapng> [--json]
                --json prints {"networks": [...], "mloGroups": [...]} with
                complete Multi-Link Operation link sets assembled per AP MLD.
              lanfi-cli har <traffic.har> [--json|--markdown] [--no-redact]
                Slowest requests, failures, p95 latency, bytes per host and the
                dominant timing phase from a browser or proxy HAR export.
                Credentials are redacted unless --no-redact is passed.
              lanfi-cli mcp
                Model Context Protocol server over stdio for AI agents.
                Exposes scan summary, analysis, protocols, channels, capture
                parsing and DNS lookups. Reads the live scan snapshot that
                the LanFi app writes to
                ~/Library/Application Support/LanFi/mcp/latest-scan.json
                or an exported scan JSON passed with the `path` argument.
              lanfi-cli help
            """
        )
    }
}

private enum CLIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

private func printJSON(_ object: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
        let text = String(data: data, encoding: .utf8)
    {
        print(text)
    }
}
