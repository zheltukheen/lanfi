import Foundation

extension MCPToolkit {
    static func iperf3(_ arguments: [String: Any]) async -> MCPToolOutcome {
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

    static func speedTest(_ arguments: [String: Any]) async -> MCPToolOutcome {
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

    static func uptime() -> MCPToolOutcome {
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

    static func diagnostics() -> MCPToolOutcome {
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

    static func info() -> MCPToolOutcome {
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
}
