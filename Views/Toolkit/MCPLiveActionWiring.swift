import AppKit
import CoreWLAN
import Foundation

// MARK: - App wiring

extension MCPLiveActionService {
    /// Registers the three handlers against the app's live view models. Called
    /// once when the toolkit appears; replacing a handler is idempotent.
    func configure(
        analyzer: AnalyzerViewModel, survey: SurveyViewModel, interfaces: InterfacesViewModel
    ) {
        register(.scanNow) { request in
            await Self.scanNow(analyzer: analyzer, request: request)
        }
        register(.startCapture) { request in
            await Self.startCapture(request: request)
        }
        register(.surveySample) { request in
            await Self.surveySample(survey: survey, request: request)
        }
    }

    private static func scanNow(
        analyzer: AnalyzerViewModel, request: MCPLiveActionRequest
    ) async -> MCPLiveActionResponse {
        if analyzer.isScanning {
            // A scan already running satisfies "scan now"; wait for it so the
            // caller gets a fresh count rather than a half-filled list.
        } else {
            analyzer.refresh()
        }
        let deadline = Date().addingTimeInterval(20)
        while analyzer.isScanning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        guard !analyzer.isScanning else {
            return MCPLiveActionResponse(
                id: request.id, action: .scanNow, ok: false,
                message: "The Wi-Fi scan did not finish within 20 seconds.")
        }
        return MCPLiveActionResponse(
            id: request.id, action: .scanNow, ok: true,
            message: "Scan finished with \(analyzer.networks.count) networks.",
            payload: ["networks": "\(analyzer.networks.count)"])
    }

    private static func startCapture(
        request: MCPLiveActionRequest
    ) async -> MCPLiveActionResponse {
        let duration = max(5, min(Int(request.arguments["duration"] ?? "") ?? 10, 120))
        let monitor = request.arguments["monitor"] == "true"
        let interface =
            request.arguments["interface"]
            ?? CWWiFiClient.shared().interface()?.interfaceName
            ?? "en0"
        let filter = request.arguments["filter"] ?? ""
        let folder = MCPLiveActionStore.defaultDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let output = folder.appendingPathComponent("mcp-\(stamp).pcap")
        let options = LiveCaptureOptions(
            interfaceName: interface, duration: duration, outputURL: output,
            monitorMode: monitor, filter: filter)
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                try await LiveCaptureService.capture(options)
            }.value
            return MCPLiveActionResponse(
                id: request.id, action: .startCapture, ok: true,
                message: "Capture finished: \(url.path)",
                payload: ["path": url.path, "duration": "\(duration)"])
        } catch {
            return MCPLiveActionResponse(
                id: request.id, action: .startCapture, ok: false,
                message: error.localizedDescription)
        }
    }

    private static func surveySample(
        survey: SurveyViewModel, request: MCPLiveActionRequest
    ) async -> MCPLiveActionResponse {
        guard !survey.samples.isEmpty else {
            return MCPLiveActionResponse(
                id: request.id, action: .surveySample, ok: false,
                message: "The active site survey has no samples to tag yet.")
        }
        let provider = CurrentLocationProvider()
        provider.request()
        let deadline = Date().addingTimeInterval(10)
        while provider.coordinate == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let coordinate = provider.coordinate else {
            return MCPLiveActionResponse(
                id: request.id, action: .surveySample, ok: false,
                message:
                    "No location fix. Allow Location for LanFi, then retry; macOS location is approximate."
            )
        }
        survey.tagLastSample(
            latitude: coordinate.latitude, longitude: coordinate.longitude)
        return MCPLiveActionResponse(
            id: request.id, action: .surveySample, ok: true,
            message: "Tagged the newest sample with the current location.",
            payload: [
                "latitude": String(format: "%.6f", coordinate.latitude),
                "longitude": String(format: "%.6f", coordinate.longitude),
                "samples": "\(survey.samples.count)",
            ])
    }
}
