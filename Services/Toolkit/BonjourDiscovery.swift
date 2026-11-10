import Darwin
import Foundation

/// Best-effort Bonjour name lookup for the LAN Scanner. It browses a small set
/// of common service types, resolves them, and maps resolved IPv4 addresses to
/// the advertised service name. A failure/timeout simply returns no names.
enum BonjourDiscovery {
    static func names(timeout: TimeInterval) async -> [String: String] {
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
        "_smb._tcp.",
        "_airplay._tcp.",
        "_ipp._tcp.",
        "_printer._tcp.",
    ]

    private var services: [NetService] = []
    private var browsers: [NetServiceBrowser] = []
    private var names: [String: String] = [:]

    func run(timeout: TimeInterval) -> [String: String] {
        for type in Self.serviceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(browser)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(timeout))

        for service in services {
            service.delegate = self
            service.resolve(withTimeout: 1)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        for browser in browsers { browser.stop() }
        return names
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
    ) {
        services.append(service)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }
        for data in addresses {
            guard let ip = Self.ipAddress(from: data) else { continue }
            names[ip] = sender.name
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
