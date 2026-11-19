import Foundation

/// P3.8 — wired/Wi-Fi link automation.
///
/// Edge-triggered only: Wi-Fi is turned off once when a physical Ethernet link
/// comes up, and turned back on once when it goes away — but only if LanFi was
/// the one that turned it off. A manual Wi-Fi change always wins.
enum LinkAutomationAction: Equatable, Sendable {
    case disableWiFi
    case enableWiFi

    var detail: String {
        switch self {
        case .disableWiFi:
            return String(localized: "Wi-Fi was turned off because an Ethernet link is active.")
        case .enableWiFi:
            return String(localized: "Wi-Fi was restored because the Ethernet link went away.")
        }
    }
}

struct LinkAutomationPolicy: Equatable {
    var isEnabled = false
    var isPaused = false
    private(set) var wiredWasConnected: Bool?
    private(set) var didDisableWiFi = false

    /// Returns the single action this sample implies, if any.
    mutating func evaluate(wiredConnected: Bool, wifiOn: Bool) -> LinkAutomationAction? {
        let previous = wiredWasConnected
        wiredWasConnected = wiredConnected

        // The user re-enabled Wi-Fi while docked: forget our intent so we do not
        // switch it back off, and do not turn it on later either.
        if didDisableWiFi, wiredConnected, wifiOn {
            didDisableWiFi = false
        }

        guard isEnabled, !isPaused else { return nil }

        switch (previous, wiredConnected) {
        case (nil, true), (false?, true):
            guard wifiOn else { return nil }
            didDisableWiFi = true
            return .disableWiFi
        case (true, false):
            guard didDisableWiFi else { return nil }
            didDisableWiFi = false
            return .enableWiFi
        default:
            return nil
        }
    }

    /// After wake macOS may have brought Wi-Fi back up. Re-apply the intent
    /// once, but never over a user who has Wi-Fi off deliberately.
    mutating func reapplyAfterWake(wiredConnected: Bool, wifiOn: Bool) -> LinkAutomationAction? {
        guard isEnabled, !isPaused, wiredConnected, wifiOn else { return nil }
        didDisableWiFi = true
        return .disableWiFi
    }
}

// MARK: - Hardware ports

struct HardwarePort: Equatable, Sendable {
    let name: String
    let device: String
}

enum HardwarePortsOutput {
    /// Parses `networksetup -listallhardwareports`.
    static func parse(_ text: String) -> [HardwarePort] {
        var ports: [HardwarePort] = []
        var name: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Hardware Port:") {
                name = line.dropFirst("Hardware Port:".count).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Device:"), let port = name {
                let device = line.dropFirst("Device:".count).trimmingCharacters(in: .whitespaces)
                if !device.isEmpty {
                    ports.append(HardwarePort(name: port, device: device))
                }
                name = nil
            }
        }
        return ports
    }
}

enum LinkAutomationClassifier {
    /// VPN, VM and bridge devices are never treated as a wired uplink.
    static let excludedDevicePrefixes = [
        "utun", "ipsec", "ppp", "bridge", "vmnet", "vmenet", "gif", "stf", "awdl", "llw", "ap", "anpi",
    ]

    static func wifiPort(_ ports: [HardwarePort]) -> HardwarePort? {
        ports.first {
            let name = $0.name.lowercased()
            return name.contains("wi-fi") || name.contains("airport")
        }
    }

    static func ethernetPorts(_ ports: [HardwarePort]) -> [HardwarePort] {
        let wifi = wifiPort(ports)?.device
        return ports.filter { port in
            guard port.device != wifi else { return false }
            guard port.device.hasPrefix("en") else { return false }
            let lower = port.device.lowercased()
            return !excludedDevicePrefixes.contains { lower.hasPrefix($0) }
        }
    }
}

// MARK: - Power output

enum AirportPowerOutput {
    static func isOn(_ text: String) -> Bool? {
        guard let colon = text.lastIndex(of: ":") else { return nil }
        let value = text[text.index(after: colon)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if value == "on" { return true }
        if value == "off" { return false }
        return nil
    }
}

enum IfconfigOutput {
    static func isActive(_ text: String) -> Bool {
        text.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("status:") else { return false }
            return trimmed.dropFirst("status:".count)
                .trimmingCharacters(in: .whitespaces) == "active"
        }
    }
}
