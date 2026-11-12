import AppKit
import Darwin
import Foundation

/// macOS gates local-network traffic — the ARP table, LAN probes, Bonjour —
/// behind Privacy & Security → Local Network. The `arp` subprocess the scanner
/// reads does not trigger that prompt on LanFi's behalf, so an in-process
/// broadcast is sent first: that access is what macOS attributes to the app and
/// what makes the permission prompt (and the Privacy entry) appear.
enum LocalNetworkAccess {
    static var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
    }

    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    /// Broadcasts a tiny datagram on the local segment. Harmless once the
    /// permission is granted; on a fresh install it raises the system prompt.
    @discardableResult
    static func request() -> Bool {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var enabled: Int32 = 1
        _ = setsockopt(
            descriptor, SOL_SOCKET, SO_BROADCAST, &enabled,
            socklen_t(MemoryLayout<Int32>.size))

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(9).bigEndian
        guard inet_pton(AF_INET, "255.255.255.255", &destination.sin_addr) == 1 else {
            return false
        }

        let payload = [UInt8](repeating: 0, count: 4)
        let sent = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                sendto(
                    descriptor, payload, payload.count, 0, address,
                    socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return sent == payload.count
    }
}
