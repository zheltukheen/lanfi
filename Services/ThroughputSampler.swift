import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// Reads cumulative interface byte counters for the menu-bar meter.
///
/// Only public APIs: `getifaddrs` for the counters, SystemConfiguration for the
/// primary service and CoreWLAN for the Wi-Fi interface name.
struct ThroughputCounterReader {
    /// Primary service interface, e.g. `en0`.
    func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "LanFi.Throughput" as CFString, nil, nil),
            let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
            let dictionary = value as? [String: Any]
        else { return nil }
        return dictionary["PrimaryInterface"] as? String
    }

    func wifiInterfaceName() -> String? {
        CWWiFiClient.shared().interface()?.interfaceName
    }

    /// Counters keyed by BSD interface name. `getifaddrs` may list an interface
    /// once per address family, so the largest counter wins.
    func counters(for names: Set<String>) -> [String: InterfaceCounters] {
        guard !names.isEmpty else { return [:] }
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [:] }
        defer { freeifaddrs(first) }

        var result: [String: InterfaceCounters] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = current {
            let interface = entry.pointee
            let name = String(cString: interface.ifa_name)
            if names.contains(name), let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                let data = interface.ifa_data
            {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                let existing = result[name] ?? InterfaceCounters(receivedBytes: 0, sentBytes: 0)
                result[name] = InterfaceCounters(
                    receivedBytes: max(existing.receivedBytes, UInt64(stats.ifi_ibytes)),
                    sentBytes: max(existing.sentBytes, UInt64(stats.ifi_obytes))
                )
            }
            current = interface.ifa_next
        }
        return result
    }
}

/// One interface's live rate, as shown in the popover.
struct MenuBarThroughput: Equatable, Identifiable {
    let interfaceName: String
    let tone: String  // "primary" / "wifi", drives the label only
    let receivedBytesPerSecond: Double
    let sentBytesPerSecond: Double

    var id: String { interfaceName + ":" + tone }
    var totalBytesPerSecond: Double { receivedBytesPerSecond + sentBytesPerSecond }
}
