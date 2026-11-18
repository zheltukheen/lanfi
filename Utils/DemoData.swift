#if DEBUG
    import Foundation

    /// Deterministic fixtures for the snapshot harness (`--demo`). Never
    /// compiled into Release and never written to disk: documentation images
    /// must not depend on the reviewer's Wi-Fi, permissions or survey files.
    enum DemoData {
        // MARK: - Wi-Fi

        static func networks() -> [NetworkModel] {
            [
                network(
                    ssid: "LanFi-Office", bssid: "74:AC:B9:11:20:06", band: .band24, channel: 6,
                    width: 20, generation: .mode11n, security: "WPA2 Personal", signal: -48,
                    noise: -92, utilization: 22, vendor: "Ubiquiti"),
                network(
                    ssid: "LanFi-Office", bssid: "74:AC:B9:11:20:44", band: .band5, channel: 44,
                    width: 80, generation: .mode11ax, security: "WPA3 Personal", signal: -51,
                    noise: -95, utilization: 18, vendor: "Ubiquiti"),
                network(
                    ssid: "LanFi-Office", bssid: "74:AC:B9:11:20:37", band: .band6, channel: 37,
                    width: 160, generation: .mode11be, security: "WPA3 Personal", signal: -55,
                    noise: -96, utilization: 9, vendor: "Ubiquiti"),
                network(
                    ssid: "Studio-Guest", bssid: "50:C7:BF:3A:01:01", band: .band24,
                    channel: 1, width: 20, generation: .mode11n, security: "Open",
                    signal: -67, noise: -90, utilization: 41, vendor: "TP-Link"),
                network(
                    ssid: "Neighbor-5G", bssid: "A0:40:A0:52:09:95", band: .band5,
                    channel: 149, width: 80, generation: .mode11ac, security: "WPA2 Personal",
                    signal: -63, noise: -93, utilization: 33, vendor: "Netgear"),
                network(
                    ssid: "Neighbor-DFS", bssid: "2C:56:DC:08:64:64", band: .band5,
                    channel: 100, width: 80, generation: .mode11ax, security: "WPA2 Personal",
                    signal: -74, noise: -94, utilization: 52, vendor: "ASUSTek"),
                network(
                    ssid: "Lab-6E", bssid: "00:1B:54:22:35:35", band: .band6, channel: 53,
                    width: 160, generation: .mode11ax, security: "WPA3 Enterprise",
                    signal: -80, noise: -97, utilization: 5, vendor: "Cisco"),
                network(
                    ssid: "Sensor-IoT", bssid: "24:0A:C4:7B:41:29", band: .band6, channel: 41,
                    width: 20, generation: .mode11ax, security: "WPA2 Personal", signal: -84,
                    noise: -98, utilization: 12, vendor: "Espressif"),
                network(
                    ssid: "Printer-2.4", bssid: "3C:52:82:0D:11:0B", band: .band24,
                    channel: 11, width: 20, generation: .mode11n, security: "WPA2 Personal",
                    signal: -76, noise: -91, utilization: 8, vendor: "HP"),
            ]
        }

        private static func network(
            ssid: String, bssid: String, band: WiFiBand, channel: Int, width: Int,
            generation: WiFiStandard, security: String, signal: Int, noise: Int,
            utilization: Int, vendor: String
        ) -> NetworkModel {
            let now = Date()
            return NetworkModel(
                id: bssid,
                bssid: bssid,
                ssid: ssid,
                band: band,
                channel: channel,
                channelWidthMHz: width,
                generation: generation,
                security: security,
                vendor: vendor,
                apName: nil,
                mode: "Infrastructure",
                signal: signal,
                noise: noise,
                snr: signal - noise,
                basicRates: nil,
                minBasicRate: nil,
                maxBasicRate: nil,
                minRate: nil,
                maxRate: nil,
                centerFrequency: nil,
                channelUtilization: utilization,
                beaconInterval: 100,
                beaconRate: nil,
                beaconAirtime: nil,
                beaconMode: "Infrastructure",
                countryCode: "US",
                fastTransition: true,
                protectionMode: nil,
                stations: nil,
                clients: 6,
                streams: 2,
                type: nil,
                wps: "Disabled",
                wpsEnabled: false,
                pmfRequired: security.hasPrefix("WPA3"),
                ieCount: nil,
                ieTotalLength: nil,
                ratesEstimated: false,
                informationElements: [],
                count: 12,
                firstSeen: now.addingTimeInterval(-3_600),
                lastSeen: now
            )
        }

        // MARK: - Survey

        static func surveyProject() -> SurveyProject {
            let bssid = "74:AC:B9:11:20:44"
            var samples: [SurveySample] = []
            for row in 0..<4 {
                for column in 0..<6 {
                    let x = 0.10 + Double(column) * 0.16
                    let y = 0.14 + Double(row) * 0.24
                    let fade = abs(Double(column) - 1.4) * 7 + abs(Double(row) - 1.2) * 9
                    samples.append(
                        SurveySample(
                            id: UUID(),
                            x: x,
                            y: y,
                            rssi: Int(-44 - fade),
                            ssid: "LanFi-Office",
                            bssid: bssid,
                            recordedAt: Date()
                        ))
                }
            }
            return SurveyProject(
                id: UUID(),
                name: "Demo office",
                imageFileName: nil,
                samples: samples,
                walls: [
                    .new(x1: 0.34, y1: 0.0, x2: 0.34, y2: 0.58),
                    .new(x1: 0.34, y1: 0.58, x2: 1.0, y2: 0.58),
                ],
                obstacles: [
                    .new(points: [
                        SurveyPoint(x: 0.62, y: 0.10), SurveyPoint(x: 0.92, y: 0.10),
                        SurveyPoint(x: 0.92, y: 0.46), SurveyPoint(x: 0.62, y: 0.46),
                    ])
                ],
                accessPoints: [
                    .new(x: 0.24, y: 0.26, band: "5GHz", channel: 44),
                    .new(x: 0.78, y: 0.72, band: "6GHz", channel: 37),
                ],
                floorLevel: 0,
                planWidthMeters: 20,
                planHeightMeters: 12,
                reportTitle: "Demo office survey",
                clientName: "LanFi QA",
                updatedAt: Date()
            )
        }

        // MARK: - Uptime

        static func uptimeSnapshot() -> (targets: [UptimeTarget], checks: [UptimeCheck]) {
            let targets = [
                UptimeTarget(
                    name: "Cloudflare DNS", address: "https://1.1.1.1", kind: .http,
                    intervalMinutes: 5),
                UptimeTarget(
                    name: "GitHub", address: "https://github.com", kind: .http,
                    intervalMinutes: 5),
                UptimeTarget(
                    name: "Office NAS", address: "192.168.1.10:443", kind: .tcp,
                    intervalMinutes: 5),
            ]

            var checks: [UptimeCheck] = []
            let now = Date()
            for (targetIndex, target) in targets.enumerated() {
                for step in 0..<24 {
                    let minutesAgo = Double(24 - step) * 5
                    let failed =
                        targetIndex == 1 && step == 15
                    checks.append(
                        UptimeCheck(
                            targetID: target.id,
                            at: now.addingTimeInterval(-minutesAgo * 60),
                            isUp: !failed,
                            latencyMilliseconds: failed
                                ? nil : 12 + Double((step + targetIndex * 3) % 9) * 3.4,
                            detail: failed ? "HTTP 503" : "HTTP 200"
                        ))
                }
            }
            return (targets, checks)
        }
    }
#endif
