import Foundation

/// A LanFi scan export (`Scan` JSON) loaded from disk. Shared by the CLI
/// commands and the MCP server.
struct ScanExport {
    let networks: [NetworkModel]

    static func load(_ url: URL) throws -> ScanExport {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["networks"] as? [[String: Any]]
        else {
            throw ScanExportError.notAScan
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
            let generation: WiFiStandard
            switch (row["generation"] as? String ?? "").lowercased() {
            case "11be", "wi-fi 7", "wifi 7": generation = .mode11be
            case "11ax", "wi-fi 6", "wifi 6": generation = .mode11ax
            case "11ac", "wi-fi 5", "wifi 5": generation = .mode11ac
            case "11n", "wi-fi 4", "wifi 4": generation = .mode11n
            case "11g": generation = .mode11g
            case "11a": generation = .mode11a
            case "11b": generation = .mode11b
            default: generation = .unknown
            }
            networks.append(
                NetworkModel(
                    summaryID: row["id"] as? String ?? bssid,
                    bssid: bssid,
                    ssid: ssid,
                    band: band,
                    channel: row["channel"] as? Int ?? 0,
                    widthMHz: row["widthMHz"] as? Int ?? 0,
                    generation: generation,
                    security: row["security"] as? String ?? "Unknown",
                    signal: row["signalDbm"] as? Int ?? -100,
                    noise: row["noiseDbm"] as? Int,
                    vendor: row["vendor"] as? String ?? "-"
                )
            )
        }
        guard !networks.isEmpty else { throw ScanExportError.noNetworks }
        return ScanExport(networks: networks)
    }

    static func loadDefault(_ path: String?) throws -> ScanExport {
        if let path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ScanExportError.missingFile(url.path)
            }
            return try load(url)
        }
        let live = MCPPaths.liveSnapshotURL
        guard FileManager.default.fileExists(atPath: live.path) else {
            throw ScanExportError.noSnapshot
        }
        return try load(live)
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
            lines.append(
                "\(network.displaySSID)\t\(network.bssid)\t\(network.band.label) ch \(network.channel)\t\(network.signal) dBm\t\(network.security)"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Full analysis for agents: per-network metrics and findings, channel
    /// recommendations and security findings.
    var analysisPayload: [String: Any] {
        let report = NetworkAnalyzer.analyze(networks: networks)
        let rows = networks.sorted { $0.signal > $1.signal }.map { network -> [String: Any] in
            let metrics = report.metrics(for: network.id)
            var row: [String: Any] = [
                "id": network.id,
                "ssid": network.displaySSID,
                "bssid": network.bssid,
                "band": network.band.label,
                "channel": network.channel,
                "widthMHz": network.channelWidthMHz,
                "generation": network.generation.label,
                "security": network.security,
                "signalDbm": network.signal,
                "noiseDbm": network.noise.map { $0 as Any } ?? NSNull(),
                "snrDb": network.snr.map { $0 as Any } ?? NSNull(),
                "vendor": network.vendor,
            ]
            if let metrics {
                row["qualityScore"] = metrics.qualityScore
                row["grade"] = metrics.grade.rawValue
                row["coChannelCount"] = metrics.coChannelCount
                row["overlappingCount"] = metrics.overlappingCount
                row["interferenceLoad"] = (metrics.interferenceLoad * 1000).rounded() / 1000
                row["issues"] = metrics.issues.map {
                    [
                        "category": String(describing: $0.category),
                        "severity": String(describing: $0.severity),
                        "title": $0.title,
                        "detail": $0.detail,
                    ]
                }
            }
            return row
        }
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
        let findings = report.securityFindings.map {
            [
                "ssid": $0.ssid,
                "bssid": $0.bssid,
                "severity": String(describing: $0.severity),
                "title": $0.title,
                "detail": $0.detail,
            ]
        }
        return [
            "networkCount": networks.count,
            "averageQuality": report.averageQuality,
            "criticalFindings": report.criticalFindingCount,
            "networks": rows,
            "recommendations": recommendations,
            "securityFindings": findings,
        ]
    }

    /// Block-oriented protocol profile for one SSID/BSSID, or for every
    /// network when no selector is given.
    func protocolPayload(ssid: String?, bssid: String?) -> [[String: Any]] {
        let selected = networks.filter { network in
            if let bssid, !bssid.isEmpty { return network.bssid.caseInsensitiveCompare(bssid) == .orderedSame }
            if let ssid, !ssid.isEmpty { return network.ssid.caseInsensitiveCompare(ssid) == .orderedSame }
            return true
        }
        return selected.map { network in
            let metrics = NetworkAnalyzer.metricsFor(network, among: networks)
            let profile = ProtocolAnalyzer.profile(for: network, metrics: metrics)
            return [
                "ssid": network.displaySSID,
                "bssid": network.bssid,
                "format": profile.formatLine,
                "warnings": profile.warnings,
                "blocks": profile.blocks.map { block in
                    [
                        "title": block.title,
                        "facts": block.facts.map {
                            [
                                "label": $0.label,
                                "value": $0.value,
                                "status": String(describing: $0.status),
                            ]
                        },
                    ]
                },
            ]
        }
    }
}

enum ScanExportError: LocalizedError {
    case notAScan
    case noNetworks
    case missingFile(String)
    case noSnapshot

    var errorDescription: String? {
        switch self {
        case .notAScan:
            return "Not a LanFi scan export (missing networks)."
        case .noNetworks:
            return "The export contains no networks."
        case .missingFile(let path):
            return "File not found: \(path)"
        case .noSnapshot:
            return
                "No live scan yet. Run LanFi, or pass path to an exported scan JSON."
        }
    }
}
