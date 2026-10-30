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

private struct ScanExport {
    let networks: [NetworkModel]

    static func load(_ url: URL) throws -> ScanExport {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["networks"] as? [[String: Any]]
        else {
            throw CLIError.message("Not a LanFi scan export (missing networks).")
        }
        var networks: [NetworkModel] = []
        for row in rows {
            guard let ssid = row["ssid"] as? String,
                let bssid = row["bssid"] as? String
            else { continue }
            let band: WiFiBand
            switch (row["band"] as? String ?? "").lowercased() {
            case "2.4ghz", "2.4": band = .band24
            case "5ghz", "5": band = .band5
            case "6ghz", "6": band = .band6
            default: band = .unknown
            }
            networks.append(
                NetworkModel(
                    summaryID: row["id"] as? String ?? bssid,
                    bssid: bssid,
                    ssid: ssid,
                    band: band,
                    channel: row["channel"] as? Int ?? 0,
                    widthMHz: row["widthMHz"] as? Int ?? 0,
                    security: row["security"] as? String ?? "Unknown",
                    signal: row["signalDbm"] as? Int ?? -100,
                    noise: row["noiseDbm"] as? Int,
                    vendor: row["vendor"] as? String ?? "-"
                )
            )
        }
        return ScanExport(networks: networks)
    }

    var summaryJSON: [[String: Any]] {
        networks.map {
            [
                "ssid": $0.displaySSID, "bssid": $0.bssid, "band": $0.band.label,
                "channel": $0.channel, "signalDbm": $0.signal, "security": $0.security,
            ]
        }
    }

    var summaryText: String {
        var lines = ["\(networks.count) networks"]
        for network in networks.sorted(by: { $0.signal > $1.signal }) {
            lines.append("\(network.displaySSID)\t\(network.bssid)\t\(network.band.label) ch \(network.channel)\t\(network.signal) dBm\t\(network.security)")
        }
        return lines.joined(separator: "\n")
    }
}

private func printJSON(_ object: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
        let text = String(data: data, encoding: .utf8)
    {
        print(text)
    }
}
