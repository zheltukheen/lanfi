#if canImport(AppIntents)
    import AppIntents
    import CoreWLAN
    import Foundation

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
                intent: LanFiSpeedTestIntent(),
                phrases: ["Run a speed test in \(.applicationName)"],
                shortTitle: "Speed test",
                systemImageName: "speedometer"
            )
        }
    }
#endif
