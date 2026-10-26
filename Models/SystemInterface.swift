import Foundation

enum InterfaceKind: String, Codable, CaseIterable, Identifiable {
    case wifi
    case ethernet
    case bridge
    case tunnel
    case loopback
    case awdl
    case cellular
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .bridge: return "Bridge"
        case .tunnel: return "Tunnel / VPN"
        case .loopback: return "Loopback"
        case .awdl: return "AWDL"
        case .cellular: return "Cellular"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .bridge: return "arrow.triangle.branch"
        case .tunnel: return "lock.shield"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .awdl: return "dot.radiowaves.left.and.right"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }

    var category: String {
        switch self {
        case .wifi, .ethernet, .cellular: return "Physical"
        case .tunnel: return "Virtual & VPN"
        case .bridge: return "Bridges"
        case .awdl: return "Peer-to-peer"
        case .loopback: return "Local"
        case .other: return "Other"
        }
    }

    var sortOrder: Int {
        switch self {
        case .wifi: return 0
        case .ethernet: return 1
        case .cellular: return 2
        case .bridge: return 3
        case .tunnel: return 4
        case .awdl: return 5
        case .loopback: return 6
        case .other: return 7
        }
    }
}

struct InterfaceAddress: Codable, Equatable, Identifiable {
    var id: String { "\(family)-\(address)" }
    let family: String
    let address: String
    let prefixLength: Int?
}

struct SystemInterface: Identifiable, Equatable, Codable {
    var id: String { bsdName }

    let bsdName: String
    let displayName: String
    let kind: InterfaceKind
    let isUp: Bool
    let isRunning: Bool
    let isPrimary: Bool
    let macAddress: String?
    let mtu: Int?
    let linkSpeedMbps: Int?
    let ipv4: [InterfaceAddress]
    let ipv6: [InterfaceAddress]
    let rxBytes: UInt64
    let txBytes: UInt64
    let rxPackets: UInt64
    let txPackets: UInt64
    let rxErrors: UInt64
    let txErrors: UInt64
    let ssid: String?
    let bssid: String?
    let rssi: Int?
    let security: String?
    let dnsServers: [String]
    let router: String?

    var statusLabel: String {
        if !isUp { return "Down" }
        if isRunning { return "Up" }
        return "No carrier"
    }

    var primaryIPv4: String? { ipv4.first?.address }
    var primaryIPv6: String? { ipv6.first?.address }

    var rxLabel: String { ByteCountFormatter.string(fromByteCount: Int64(rxBytes), countStyle: .binary) }
    var txLabel: String { ByteCountFormatter.string(fromByteCount: Int64(txBytes), countStyle: .binary) }

    var speedLabel: String? {
        guard let linkSpeedMbps, linkSpeedMbps > 0 else { return nil }
        if linkSpeedMbps >= 1000 {
            return String(format: "%.1f Gbps", Double(linkSpeedMbps) / 1000.0)
        }
        return "\(linkSpeedMbps) Mbps"
    }

    var wifiSummary: String? {
        guard kind == .wifi else { return nil }
        let name = ssid?.isEmpty == false ? ssid! : "Hidden"
        let signal = rssi.map { " · \($0) dBm" } ?? ""
        return "\(name)\(signal)"
    }
}

struct InterfacesReport: Equatable, Codable {
    let generatedAt: Date
    let interfaces: [SystemInterface]
    let primaryInterface: String?
    let dnsServers: [String]
    let router: String?

    static let empty = InterfacesReport(
        generatedAt: .distantPast,
        interfaces: [],
        primaryInterface: nil,
        dnsServers: [],
        router: nil
    )

    var upCount: Int { interfaces.filter(\.isUp).count }
    var physicalCount: Int { interfaces.filter { $0.kind == .wifi || $0.kind == .ethernet }.count }
    var tunnelCount: Int { interfaces.filter { $0.kind == .tunnel }.count }

    var grouped: [(String, [SystemInterface])] {
        let groups = Dictionary(grouping: interfaces) { $0.kind.category }
        return groups.keys.sorted { lhs, rhs in
            let left = groups[lhs]?.map(\.kind.sortOrder).min() ?? 99
            let right = groups[rhs]?.map(\.kind.sortOrder).min() ?? 99
            return left < right
        }.map { ($0, groups[$0]?.sorted { $0.kind.sortOrder < $1.kind.sortOrder } ?? []) }
    }
}

enum InterfaceClassifier {
    static func kind(name: String, type: String?, hardware: String?) -> InterfaceKind {
        let lower = (type ?? "").lowercased()
        let interface = name.lowercased()
        if lower.contains("ieee80211")
            || interface == "en0" && lower.contains("ethernet") && hardware?.contains("AirPort") == true
        {
            return .wifi
        }
        if lower.contains("80211") || lower.contains("airport") { return .wifi }
        if lower.contains("ethernet") || lower.contains("firewire") { return .ethernet }
        if lower.contains("bridge") || interface.hasPrefix("bridge") { return .bridge }
        if lower.contains("tunnel") || lower.contains("ppp") || lower.contains("ipsec") || lower.contains("l2tp")
            || lower.contains("gre") || interface.hasPrefix("utun") || interface.hasPrefix("ipsec")
        {
            return .tunnel
        }
        if lower.contains("loopback") || interface == "lo0" { return .loopback }
        if interface.hasPrefix("awdl") { return .awdl }
        if lower.contains("wwan") || lower.contains("cellular") || interface.hasPrefix("pdp_ip") { return .cellular }
        if interface.hasPrefix("llw") || interface.hasPrefix("anpi") { return .awdl }
        return .other
    }

    static func prefixLength(netmask: String) -> Int? {
        let parts = netmask.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        var bits = 0
        for part in parts {
            bits += part.nonzeroBitCount
        }
        return bits
    }
}
