import LanFiCore
import CoreWLAN
import Foundation

struct PassiveScanResult {
    let networks: [NetworkModel]
    let visitedChannels: [ScanChannelPlanItem]
    let notes: [String]
    let duration: TimeInterval

    var summary: String {
        let count = networks.count
        let channels = visitedChannels.count
        return String(
            localized:
                "\(count) networks from \(channels) \(channels == 1 ? "channel" : "channels")"
        )
    }
}

enum PassiveScanError: LocalizedError {
    case planEmpty
    case activeMode
    case interfaceNotFound
    case authorizationCancelled
    case captureFailed(String)
    case emptyCapture
    case inProgress

    var errorDescription: String? {
        switch self {
        case .planEmpty:
            return String(localized: "The channel plan is empty.")
        case .activeMode:
            return String(localized: "Active mode uses the normal CoreWLAN scan.")
        case .interfaceNotFound:
            return String(localized: "Wi-Fi interface not found.")
        case .authorizationCancelled:
            return String(localized: "Administrator authorization was cancelled.")
        case .captureFailed(let message):
            return message
        case .emptyCapture:
            return String(
                localized:
                    "The monitor capture wrote no frames. Check that Wi-Fi is on and the interface supports monitor mode."
            )
        case .inProgress:
            return String(localized: "A passive scan is already running.")
        }
    }
}

/// Passive scanner: one privileged monitor-mode capture while the app tunes the
/// radio through the channel plan with public CoreWLAN APIs, then offline
/// 802.11 beacon parsing with `PcapAnalyzer`.
///
/// macOS has no unprivileged BPF access, so the capture asks for one-off
/// administrator authorization, exactly like the Capture tab. Nothing is
/// installed and no credentials are stored.
actor PassiveScanEngine {
    typealias ProgressHandler = @Sendable (PassiveScanProgress) -> Void

    private var isRunning = false

    func scan(
        plan: ScanChannelPlan,
        interfaceName: String? = nil,
        progress: @escaping ProgressHandler
    ) async throws -> PassiveScanResult {
        guard plan.mode != .active else { throw PassiveScanError.activeMode }
        guard !plan.items.isEmpty else { throw PassiveScanError.planEmpty }
        guard !isRunning else { throw PassiveScanError.inProgress }
        isRunning = true
        defer { isRunning = false }

        let client = CWWiFiClient.shared()
        let preferred = UserDefaults.standard.string(forKey: AppSettingsKey.wifiInterface.rawValue)
            .flatMap { $0.isEmpty ? nil : $0 }
        let resolvedName =
            interfaceName ?? preferred ?? client.interfaceNames()?.sorted().first
        guard let resolvedName, let interface = client.interface(withName: resolvedName) else {
            throw PassiveScanError.interfaceNotFound
        }

        progress(
            PassiveScanProgress(
                phase: .preparing, completed: 0, total: plan.items.count,
                channel: plan.items.first))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanFi-passive-\(UUID().uuidString).pcap")
        let logURL = URL(fileURLWithPath: outputURL.path + ".log")
        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: logURL)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: logURL)
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: outputURL.path + ".pid"))
        }

        let dwell = TimeInterval(plan.items.first?.dwellMilliseconds ?? 150) / 1000
        let captureDuration = max(3, plan.totalDuration + 2)
        let script = Self.captureScript(
            interfaceName: resolvedName, outputURL: outputURL, logURL: logURL,
            duration: captureDuration)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \(Self.appleScriptQuote(script)) with administrator privileges",
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        let started = Date()
        async let exitStatus = Self.run(process)

        // tcpdump needs a moment to put the interface into monitor mode before
        // the first channel change.
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        var visited: [ScanChannelPlanItem] = []
        var notes: [String] = []
        for (index, item) in plan.items.enumerated() {
            if Task.isCancelled { break }
            if !hop(interface: interface, to: item) {
                notes.append(
                    String(
                        localized:
                            "Could not tune \(resolvedName) to \(item.channelLabel); that channel may be missing."
                    ))
            }
            visited.append(item)
            progress(
                PassiveScanProgress(
                    phase: .capturing, completed: index, total: plan.items.count,
                    channel: item))
            try? await Task.sleep(nanoseconds: UInt64(max(0.05, dwell) * 1_000_000_000))
        }

        let status = await exitStatus
        let errorText = String(
            decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard status == 0 else {
            if errorText.localizedCaseInsensitiveContains("cancel") {
                throw PassiveScanError.authorizationCancelled
            }
            throw PassiveScanError.captureFailed(
                errorText.isEmpty ? String(localized: "Monitor capture failed.") : errorText)
        }

        let size =
            (try? FileManager.default.attributesOfItem(atPath: outputURL.path))?[.size]
            as? NSNumber
        guard (size?.intValue ?? 0) > 24 else { throw PassiveScanError.emptyCapture }

        progress(
            PassiveScanProgress(
                phase: .reading, completed: plan.items.count, total: plan.items.count,
                channel: plan.items.last))

        let beacons = try PcapAnalyzer.parse(data: PcapAnalyzer.mappedData(at: outputURL))
        let networks = Self.networks(from: beacons)
        let duration = Date().timeIntervalSince(started)
        progress(
            PassiveScanProgress(
                phase: .finished, completed: plan.items.count, total: plan.items.count,
                channel: nil))

        if networks.isEmpty {
            notes.append(
                String(
                    localized:
                        "No beacon frames were decoded. Another app may hold the interface in monitor mode."
                ))
        }

        return PassiveScanResult(
            networks: networks, visitedChannels: visited, notes: notes, duration: duration)
    }

    // MARK: - Channel tuning

    private func hop(interface: CWInterface, to item: ScanChannelPlanItem) -> Bool {
        guard let channels = interface.supportedWLANChannels() else { return false }
        let exact = channels.first {
            $0.channelNumber == item.channel && Self.band($0.channelBand) == item.band
        }
        guard let channel = exact ?? channels.first(where: { $0.channelNumber == item.channel })
        else { return false }
        do {
            try interface.setWLANChannel(channel)
            return true
        } catch {
            return false
        }
    }

    private static func band(_ band: CWChannelBand?) -> WiFiBand {
        switch band {
        case .band2GHz: return .band24
        case .band5GHz: return .band5
        case .band6GHz: return .band6
        default: return .unknown
        }
    }

    // MARK: - Beacon mapping

    /// Converts captured beacons into table rows. Beacons from monitor mode
    /// carry no CoreWLAN metadata, so width and rates stay empty; everything
    /// IE-derived (6 GHz power mode, RNR, WPS, PMF) is parsed as usual.
    static func networks(from beacons: [CapturedBeacon]) -> [NetworkModel] {
        beacons.compactMap { beacon in
            guard let channel = beacon.channel, channel > 0 else { return nil }
            let band = band(forChannel: channel, frequencyMHz: beacon.frequencyMHz)
            guard band != .unknown else { return nil }
            let ssid = beacon.ssid == "Hidden" ? "" : beacon.ssid
            let bssid = beacon.bssid.uppercased()
            let generation: WiFiStandard
            if beacon.isEHT {
                generation = .mode11be
            } else if band == .band6 {
                generation = .mode11ax
            } else {
                generation = .unknown
            }
            let now = Date()
            return NetworkModel(
                id: bssid.isEmpty ? "\(ssid)|\(band.rawValue)|\(channel)" : bssid,
                bssid: bssid,
                ssid: ssid,
                band: band,
                channel: channel,
                channelWidthMHz: 0,
                generation: generation,
                security: beacon.security,
                vendor: bssid.isEmpty ? "-" : OUIParser.vendor(for: bssid),
                apName: APNameDetector.name(
                    for: beacon.informationElements, ssid: ssid,
                    vendor: bssid.isEmpty ? "-" : OUIParser.vendor(for: bssid)),
                mode: "Infrastructure",
                signal: beacon.rssi ?? -100,
                noise: nil,
                snr: nil,
                basicRates: nil,
                minBasicRate: nil,
                maxBasicRate: nil,
                minRate: nil,
                maxRate: nil,
                centerFrequency: beacon.frequencyMHz
                    ?? centerFrequency(channel: channel, band: band),
                channelUtilization: nil,
                beaconInterval: nil,
                beaconRate: nil,
                beaconAirtime: nil,
                beaconMode: "Passive",
                countryCode: nil,
                fastTransition: nil,
                protectionMode: nil,
                stations: nil,
                clients: beacon.clientCount,
                streams: nil,
                type: nil,
                wps: nil,
                wpsEnabled: nil,
                pmfRequired: nil,
                ieCount: beacon.informationElements.count,
                ieTotalLength: nil,
                ratesEstimated: false,
                informationElements: beacon.informationElements,
                count: 0,
                firstSeen: now,
                lastSeen: now
            )
        }
    }

    static func band(forChannel channel: Int, frequencyMHz: Int?) -> WiFiBand {
        if let frequencyMHz {
            switch frequencyMHz {
            case 2400...2500: return .band24
            case 4900...5925: return .band5
            case 5926...7125: return .band6
            default: break
            }
        }
        if (1...14).contains(channel) { return .band24 }
        if (32...177).contains(channel) { return .band5 }
        if (1...233).contains(channel) { return .band6 }
        return .unknown
    }

    private static func centerFrequency(channel: Int, band: WiFiBand) -> Int? {
        switch band {
        case .band24: return channel == 14 ? 2484 : 2407 + channel * 5
        case .band5: return 5000 + channel * 5
        case .band6: return 5950 + channel * 5
        case .unknown: return nil
        }
    }

    // MARK: - Process helpers

    private static func run(_ process: Process) async -> Int32 {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    private static func captureScript(
        interfaceName: String, outputURL: URL, logURL: URL, duration: TimeInterval
    ) -> String {
        let name = shellQuote(interfaceName)
        let output = shellQuote(outputURL.path)
        let log = shellQuote(logURL.path)
        let pidFile = shellQuote(outputURL.path + ".pid")
        let seconds = String(format: "%.1f", max(2, duration))
        return [
            "/usr/sbin/tcpdump -i \(name) -I -y IEEE802_11_RADIO -s 0 -U -w \(output) 2> \(log) & PID=$!",
            "echo $PID > \(pidFile); chmod 644 \(pidFile) 2>/dev/null || true",
            "sleep \(seconds)",
            "kill -TERM $PID 2>/dev/null || true",
            "for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 $PID 2>/dev/null || break; sleep 0.2; done",
            "kill -KILL $PID 2>/dev/null || true",
            "wait $PID 2>/dev/null || true",
            "chown \(getuid()):\(getgid()) \(output) 2>/dev/null || true",
            "chown \(getuid()):\(getgid()) \(log) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\""
            + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            + "\""
    }
}
