import Foundation
import LanFiCore

struct MultiSensorCaptureResult {
    struct Failure: Equatable {
        let sensor: String
        let message: String
    }

    /// Nil when no sensor delivered frames, so the caller never points at a
    /// file that only contains interface blocks.
    let mergedURL: URL?
    let packetCount: Int
    let sensorNames: [String]
    let failures: [Failure]
}

/// G3: captures the same channel-window from several saved sensors and merges
/// the results into one pcapng.
///
/// Captures run one after another rather than in parallel: a capture holds one
/// ssh session per sensor for its whole duration, and sequential runs keep the
/// remote hosts independent of each other. A sensor that fails is recorded and
/// skipped, so one unreachable WLAN Pi does not throw away the others.
enum MultiSensorCaptureService {
    struct Settings {
        var interfaceName = "en0"
        var duration = 20
        var monitorMode = true
        var filter = ""

        static let `default` = Settings()
    }

    static func request(for sensor: RemoteSensor, settings: Settings) -> RemoteCaptureRequest {
        RemoteCaptureRequest(
            sensor: sensor, interfaceName: settings.interfaceName, duration: settings.duration,
            monitorMode: settings.monitorMode, filter: settings.filter)
    }

    static func capture(
        sensors: [RemoteSensor], settings: Settings, mergedURL: URL,
        progress: (@MainActor (Int, String) -> Void)? = nil
    ) async throws -> MultiSensorCaptureResult {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var sources: [CaptureSource] = []
        var failures: [MultiSensorCaptureResult.Failure] = []

        for (index, sensor) in sensors.enumerated() {
            await progress?(index, sensor.name)
            let url = directory.appendingPathComponent("\(safeFileName(sensor.name))-\(index).pcap")
            do {
                try await RemoteCaptureService.capture(
                    request(for: sensor, settings: settings), localURL: url)
                let data = try Data(contentsOf: url)
                let capture = try PcapFile.parse([UInt8](data))
                guard capture.linkType == 105 || capture.linkType == 127 else {
                    failures.append(
                        .init(
                            sensor: sensor.name,
                            message: String(
                                format: String(
                                    localized:
                                        "Captured link type %lld, not 802.11. Turn monitor mode on, or pick the monitor interface."
                                ), capture.linkType)))
                    continue
                }
                sources.append(
                    CaptureSource(
                        name: sensor.name, detail: "\(sensor.username)@\(sensor.host)",
                        capture: capture))
            } catch {
                failures.append(.init(sensor: sensor.name, message: error.localizedDescription))
            }
        }

        guard !sources.isEmpty else {
            return MultiSensorCaptureResult(
                mergedURL: nil, packetCount: 0, sensorNames: [], failures: failures)
        }

        let merged = try PcapMerge.merge(sources)
        try Data(merged.pcapng).write(to: mergedURL, options: .atomic)
        return MultiSensorCaptureResult(
            mergedURL: mergedURL, packetCount: merged.packetCount,
            sensorNames: merged.sensorNames, failures: failures)
    }

    /// Sensor names are user-supplied, so they cannot be pasted into a path.
    static func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(
            name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "sensor" : String(trimmed.prefix(40))
    }
}
