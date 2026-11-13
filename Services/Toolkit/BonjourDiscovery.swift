import Darwin
import Foundation

/// Best-effort Bonjour discovery for the LAN Scanner. It browses a small set
/// of common service types, resolves them, and maps resolved IPv4 addresses to
/// a display name plus the services the device advertises. A failure/timeout
/// simply returns no information.
enum BonjourDiscovery {
    static func names(timeout: TimeInterval) async -> [String: String] {
        await advertisements(timeout: timeout).compactMapValues(\.name)
    }

    static func advertisements(timeout: TimeInterval) async -> [String: LANAdvertisement] {
        await Task.detached(priority: .utility) {
            BonjourResolver().run(timeout: timeout)
        }.value
    }
}

private final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private static let serviceTypes = [
        "_http._tcp.",
        "_https._tcp.",
        "_ssh._tcp.",
        "_sftp-ssh._tcp.",
        "_smb._tcp.",
        "_afpovertcp._tcp.",
        "_airplay._tcp.",
        "_raop._tcp.",
        "_googlecast._tcp.",
        "_spotify-connect._tcp.",
        "_sonos._tcp.",
        "_ipp._tcp.",
        "_ipps._tcp.",
        "_printer._tcp.",
        "_pdl-datastream._tcp.",
        "_workstation._tcp.",
        "_device-info._tcp.",
        "_hap._tcp.",
        "_matter._tcp.",
        "_companion-link._tcp.",
        "_sleep-proxy._udp.",
    ]

    private var services: [(service: NetService, label: String?)] = []
    private var browsers: [NetServiceBrowser] = []
    private var advertisements: [String: LANAdvertisement] = [:]

    func run(timeout: TimeInterval) -> [String: LANAdvertisement] {
        for type in Self.serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(max(0.2, timeout)))

        for entry in services {
            entry.service.delegate = self
            entry.service.resolve(withTimeout: 0.8)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        for browser in browsers { browser.stop() }
        return advertisements
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
    ) {
        let label = LANServiceCatalog.label(forBonjourType: service.type)
        services.append((service, label))
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        let label = LANServiceCatalog.label(forBonjourType: sender.type)
        let advertisement = LANAdvertisement(
            name: sender.name,
            services: label.map { [$0] } ?? []
        )
        for data in addresses {
            guard let ip = Self.ipAddress(from: data) else { continue }
            if let existing = advertisements[ip] {
                advertisements[ip] = existing.merged(with: advertisement)
            } else {
                advertisements[ip] = advertisement
            }
        }
    }

    private static func ipAddress(from data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
            if family == sa_family_t(AF_INET) {
                var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil
                else { return nil }
                return String(cString: buffer)
            }
            if family == sa_family_t(AF_INET6) {
                var address = base.assumingMemoryBound(to: sockaddr_in6.self).pointee.sin6_addr
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil
                else { return nil }
                return String(cString: buffer)
            }
            return nil
        }
    }
}
