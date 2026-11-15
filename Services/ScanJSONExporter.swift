import Foundation

/// Shape shared by the JSON export and the MCP live snapshot. Keeping it out
/// of the view model lets the encoding run on a background task.
struct ScanJSONExporter {
    let version: String
    let analysis: AnalysisReport

    func make(networks: [NetworkModel]) -> [String: Any] {
        [
            "generator": "LanFi",
            "version": version,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "summary": [
                "networks": networks.count,
                "averageQuality": analysis.averageQuality,
                "criticalSecurityFindings": analysis.criticalFindingCount,
            ],
            "networks": networks.map(networkJSON),
            "recommendations": WiFiBand.allCases.compactMap { band -> [String: Any]? in
                guard let best = analysis.bestChannel(for: band) else { return nil }
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
            },
        ]
    }

    private func networkJSON(_ network: NetworkModel) -> [String: Any] {
        var object: [String: Any] = [
            "id": network.id,
            "ssid": network.ssid,
            "bssid": network.bssid,
            "vendor": network.vendor,
            "band": network.band.label,
            "channel": network.channel,
            "widthMHz": network.channelWidthMHz,
            "generation": network.generation.label,
            "security": network.security,
            "signalDbm": network.signal,
            "noiseDbm": network.noise.map { $0 as Any } ?? NSNull(),
            "snrDb": network.snr.map { $0 as Any } ?? NSNull(),
            "channelUtilizationPercent": network.channelUtilization.map { $0 as Any } ?? NSNull(),
            "countryCode": network.countryCode.map { $0 as Any } ?? NSNull(),
            "wpsEnabled": network.wpsEnabled.map { $0 as Any } ?? NSNull(),
            "pmfRequired": network.pmfRequired.map { $0 as Any } ?? NSNull(),
            "firstSeen": network.firstSeen.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
            "lastSeen": network.lastSeen.map { ISO8601DateFormatter().string(from: $0) as Any } ?? NSNull(),
            "informationElements": network.informationElements.map { element in
                [
                    "id": element.elementId,
                    "name": element.name,
                    "length": element.length,
                    "summary": element.summary,
                ]
            },
        ]
        if let metrics = analysis.metrics(for: network.id) {
            object["qualityScore"] = metrics.qualityScore
            object["congestionScore"] = metrics.congestionScore
            object["securityScore"] = metrics.securityScore
            object["overlappingNetworks"] = metrics.overlappingCount
            object["issues"] = metrics.issues.map {
                ["severity": $0.severity.label, "title": $0.title, "detail": $0.detail]
            }
        }
        return object
    }
}
