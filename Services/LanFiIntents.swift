#if canImport(AppIntents)
    import AppIntents
    import CoreWLAN
    import Foundation
    import LanFiCore
    import UniformTypeIdentifiers

    /// App Intents keep LanFi usable from Shortcuts without a visible window.
    /// They only read the radio, exactly like the app; nothing is uploaded.
    @available(macOS 13.0, *)
    struct LanFiScanSummaryIntent: AppIntent {
        static var title: LocalizedStringResource = "Scan Wi-Fi networks"
        static var description = IntentDescription(
            "Counts nearby Wi-Fi networks and names the strongest one.")
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            let networks = try await WiFiScanner().scan()
            guard let strongest = networks.max(by: { $0.signal < $1.signal }) else {
                return .result(dialog: IntentDialog(stringLiteral: "No Wi-Fi networks were found."))
            }
            let message =
                "\(networks.count) networks. Strongest: \(strongest.displaySSID), "
                + "\(strongest.signal) dBm on channel \(strongest.channel)."
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }

    @available(macOS 13.0, *)
    struct LanFiConnectedNetworkIntent: AppIntent {
        static var title: LocalizedStringResource = "Tell me the connected network"
        static var description = IntentDescription(
            "Reports the SSID, BSSID, signal and channel of the current Wi-Fi link.")
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            guard let interface = CWWiFiClient.shared().interface() else {
                return .result(dialog: IntentDialog(stringLiteral: "No Wi-Fi interface is available."))
            }
            let ssid = interface.ssid() ?? "Hidden network"
            let bssid = interface.bssid() ?? "unknown BSSID"
            let message =
                "\(ssid) (\(bssid)) at \(Int(interface.rssiValue())) dBm on channel "
                + "\(interface.wlanChannel()?.channelNumber ?? 0)."
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }

    @available(macOS 13.0, *)
    struct LanFiSpeedTestIntent: AppIntent {
        static var title: LocalizedStringResource = "Run a speed test"
        static var description = IntentDescription(
            "Runs networkQuality and reports download, upload and latency.")
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            do {
                let report = try await ThroughputTester.run(timeout: 15)
                return .result(dialog: IntentDialog(stringLiteral: report.summary))
            } catch {
                return .result(
                    dialog: IntentDialog(
                        stringLiteral: "Speed test failed: \(error.localizedDescription)"))
            }
        }
    }

    /// P3.3: a Shortcut can branch on the current connectivity state.
    @available(macOS 13.0, *)
    struct LanFiConnectivityStateIntent: AppIntent {
        static var title: LocalizedStringResource = "Check the internet connection"
        static var description = IntentDescription(
            "Probes the internet and reports online, captive portal or offline.")
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ProvidesDialog {
            let settings = AppSettingsStore.shared.settings.connectivity
            let probe = ConnectivityHTTPProbe()
            var outcome = await probe.probe(urlString: settings.primaryProbeURL)
            if outcome.didFail {
                outcome = await probe.probe(urlString: settings.fallbackProbeURL)
            }
            let verdict = ConnectivityProbeClassifier.classify(outcome)
            let latency = outcome.latencyMilliseconds.map { " \($0) ms" } ?? ""
            return .result(
                dialog: IntentDialog(stringLiteral: verdict.title + latency))
        }
    }

    /// P1.7: a Shortcut can hand the current scan to Files or another app
    /// without opening LanFi. Columns match the app's default scan export.
    @available(macOS 13.0, *)
    struct LanFiExportScanIntent: AppIntent {
        static var title: LocalizedStringResource = "Export the Wi-Fi scan"
        static var description = IntentDescription(
            "Scans nearby networks and returns a CSV file with SSID, BSSID, band, channel, signal, security and vendor."
        )
        static var openAppWhenRun: Bool = false

        func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
            let networks = try await WiFiScanner().scan()
            let header = "ssid,bssid,band,channel,width_mhz,signal_dbm,security,vendor"
            let rows = networks.map { network in
                [
                    network.ssid, network.bssid, network.bandLabel, String(network.channel),
                    String(network.channelWidthMHz), String(network.signal), network.security,
                    network.vendor ?? "",
                ].map(Self.csvField).joined(separator: ",")
            }
            let csv = ([header] + rows).joined(separator: "\r\n") + "\r\n"
            let file = IntentFile(
                data: Data(csv.utf8),
                filename: "LanFi-scan-\(Self.dateStamp()).csv",
                type: .commaSeparatedText
            )
            return .result(
                value: file,
                dialog: "Exported \(networks.count) networks as CSV.")
        }

        private static func csvField(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        private static func dateStamp() -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: Date())
        }
    }

    @available(macOS 13.0, *)
    struct LanFiAppShortcuts: AppShortcutsProvider {
        static var appShortcuts: [AppShortcut] {
            AppShortcut(
                intent: LanFiScanSummaryIntent(),
                phrases: ["Scan Wi-Fi in \(.applicationName)"],
                shortTitle: "Scan Wi-Fi",
                systemImageName: "wifi"
            )
            AppShortcut(
                intent: LanFiConnectedNetworkIntent(),
                phrases: ["What network am I on in \(.applicationName)"],
                shortTitle: "Connected network",
                systemImageName: "wifi.circle"
            )
            AppShortcut(
                intent: LanFiConnectivityStateIntent(),
                phrases: ["Check the internet in \(.applicationName)"],
                shortTitle: "Connectivity",
                systemImageName: "network"
            )
            AppShortcut(
                intent: LanFiSpeedTestIntent(),
                phrases: ["Run a speed test in \(.applicationName)"],
                shortTitle: "Speed test",
                systemImageName: "speedometer"
            )
            AppShortcut(
                intent: LanFiExportScanIntent(),
                phrases: ["Export the Wi-Fi scan in \(.applicationName)"],
                shortTitle: "Export scan",
                systemImageName: "square.and.arrow.up"
            )
        }
    }
#endif
