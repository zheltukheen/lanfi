import Foundation

extension MCPToolkit {
    // MARK: - Scan analysis

    static func scanSummary(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            return .json(["networks": scan.summaryJSON])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func analyze(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            return .json(scan.analysisPayload)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func protocols(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func channels(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func capture(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func har(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func spectrum(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func devices(_ arguments: [String: Any]) -> MCPToolOutcome {
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

    static func clientAnalytics(_ arguments: [String: Any]) -> MCPToolOutcome {
        do {
            let scan = try ScanExport.loadDefault(string(arguments, "path"))
            let snapshot = ClientAnalyticsSnapshot.build(networks: scan.networks)
            let accessPoints = snapshot.busiestAccessPoints.map { row -> [String: Any] in
                [
                    "bssid": row.bssid,
                    "ssid": row.ssid,
                    "band": row.band,
                    "channel": row.channel,
                    "clients": row.clients,
                    "utilizationPercent": row.utilization as Any,
                    "rssi": row.signal,
                ]
            }
            return .json([
                "advertisedClients": snapshot.advertisedClients,
                "accessPoints": snapshot.accessPointCount,
                "reportingAccessPoints": snapshot.busiestAccessPoints.count,
                "idleAccessPoints": snapshot.idleAccessPoints,
                "accessPointLoad": accessPoints,
                "insights": snapshot.insights,
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func surveyPlan(_ arguments: [String: Any]) -> MCPToolOutcome {
        let request = SurveyPlanRequest(
            widthMeters: max(1, double(arguments, "widthMeters") ?? 20),
            heightMeters: max(1, double(arguments, "heightMeters") ?? 12),
            targetRSSI: int(arguments, "targetRSSI") ?? -65,
            txPowerDbm: double(arguments, "txPowerDbm") ?? 20,
            band: string(arguments, "band") ?? "5GHz",
            channel: int(arguments, "channel") ?? 36
        )
        let plan = SurveyPlanner.plan(request)
        return .json([
            "accessPointCount": plan.accessPointCount,
            "radiusMeters": (plan.radiusMeters * 10).rounded() / 10,
            "spacingMeters": (plan.spacingMeters * 10).rounded() / 10,
            "estimatedCoveragePercent": (plan.estimatedCoveragePercent * 10).rounded() / 10,
            "accessPoints": plan.accessPoints.map { ["x": $0.x, "y": $0.y] },
            "notes": plan.notes,
        ])
    }

    static func openConnections(_ arguments: [String: Any]) async -> MCPToolOutcome {
        do {
            let rows = try await OpenConnectionsService.fetch(
                includeListeners: flag(arguments, "listeners"))
            let limit = max(1, min(int(arguments, "limit") ?? 500, 2000))
            let groups = OpenConnectionsParser.byProcess(rows).map { group in
                ["process": group.process, "connections": group.count] as [String: Any]
            }
            return .json([
                "count": rows.count,
                "returned": min(rows.count, limit),
                "processes": groups,
                "connections": rows.prefix(limit).map { row -> [String: Any] in
                    [
                        "process": row.process,
                        "pid": row.pid,
                        "user": row.user,
                        "protocol": row.protocolName,
                        "local": row.local,
                        "remote": row.remote,
                        "state": row.state,
                    ]
                },
            ])
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func name(_ severity: DeviceRiskFinding.Severity) -> String {
        switch severity {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        case .info: return "info"
        }
    }
}
