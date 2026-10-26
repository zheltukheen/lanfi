import Foundation

enum MenuBarAlertSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    static func < (lhs: MenuBarAlertSeverity, rhs: MenuBarAlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct MenuBarAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: MenuBarAlertSeverity
}

enum MenuBarAlertEngine {
    static let weakSignalThreshold = -75

    static func compute(
        networks: [NetworkModel],
        connectedBSSID: String?,
        weakSignalEnabled: Bool,
        openNetworkEnabled: Bool,
        channelChangeEnabled: Bool,
        previousChannel: Int?
    ) -> [MenuBarAlert] {
        var alerts: [MenuBarAlert] = []
        let connected = networks.first { $0.bssid == connectedBSSID }

        if weakSignalEnabled, let connected, connected.signal <= weakSignalThreshold {
            alerts.append(
                MenuBarAlert(
                    id: "weak-signal",
                    title: "Weak Wi-Fi signal",
                    detail: "\(connected.displaySSID) is \(connected.signal) dBm. Move closer or switch band.",
                    severity: .critical
                )
            )
        }

        if openNetworkEnabled {
            let open = networks.filter {
                let security = $0.security.lowercased()
                return security.contains("open") || security.contains("none")
            }
            if !open.isEmpty {
                alerts.append(
                    MenuBarAlert(
                        id: "open-network",
                        title: "\(open.count) open network\(open.count == 1 ? "" : "s")",
                        detail: open.prefix(3).map(\.displaySSID).joined(separator: ", "),
                        severity: .warning
                    )
                )
            }
        }

        if channelChangeEnabled, let connected, let previousChannel, previousChannel != connected.channel {
            alerts.append(
                MenuBarAlert(
                    id: "channel-change",
                    title: "Connected channel changed",
                    detail: "\(connected.displaySSID): channel \(previousChannel) → \(connected.channel).",
                    severity: .info
                )
            )
        }

        return alerts.sorted { $0.severity > $1.severity }
    }
}
