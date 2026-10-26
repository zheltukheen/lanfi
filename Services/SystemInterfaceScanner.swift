import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

enum SystemInterfaceScanner {
    static func scan() -> InterfacesReport {
        let wifiNames = Set(CWWiFiClient.shared().interfaceNames() ?? [])
        let routes = systemRoutes()
        let scInfo = systemConfigurationInterfaces()
        var accumulators: [String: Accumulator] = [:]

        var pointer: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&pointer) == 0, let first = pointer {
            defer { freeifaddrs(first) }
            var current: UnsafeMutablePointer<ifaddrs>? = first
            while let entry = current {
                let interface = entry.pointee
                let name = String(cString: interface.ifa_name)
                var accumulator = accumulators[name] ?? Accumulator(name: name)
                accumulator.flags = interface.ifa_flags
                if let address = interface.ifa_addr {
                    let family = address.pointee.sa_family
                    if family == UInt8(AF_LINK) {
                        if let data = interface.ifa_data {
                            let stats = data.assumingMemoryBound(to: if_data.self).pointee
                            accumulator.rxBytes = max(accumulator.rxBytes, UInt64(stats.ifi_ibytes))
                            accumulator.txBytes = max(accumulator.txBytes, UInt64(stats.ifi_obytes))
                            accumulator.rxPackets = max(accumulator.rxPackets, UInt64(stats.ifi_ipackets))
                            accumulator.txPackets = max(accumulator.txPackets, UInt64(stats.ifi_opackets))
                            accumulator.rxErrors = max(accumulator.rxErrors, UInt64(stats.ifi_ierrors))
                            accumulator.txErrors = max(accumulator.txErrors, UInt64(stats.ifi_oerrors))
                            let baud = UInt64(stats.ifi_baudrate)
                            if baud > 0 { accumulator.linkSpeedMbps = Int(baud / 1_000_000) }
                        }
                        if accumulator.macAddress == nil {
                            accumulator.macAddress = linkLayerAddress(address)
                        }
                    } else if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                        if let host = numericHost(address), !host.isEmpty {
                            let familyName = family == UInt8(AF_INET) ? "IPv4" : "IPv6"
                            let prefix = interface.ifa_netmask.flatMap(netmaskPrefix)
                            let item = InterfaceAddress(
                                family: familyName,
                                address: host,
                                prefixLength: prefix
                            )
                            if familyName == "IPv4" {
                                if !accumulator.ipv4.contains(item) { accumulator.ipv4.append(item) }
                            } else if !accumulator.ipv6.contains(item) {
                                accumulator.ipv6.append(item)
                            }
                        }
                    }
                }
                accumulators[name] = accumulator
                current = interface.ifa_next
            }
        }

        let interfaces = accumulators.values.map { accumulator -> SystemInterface in
            let interface = CWWiFiClient.shared().interface(withName: accumulator.name)
            let isWiFi = wifiNames.contains(accumulator.name)
            let kind = InterfaceClassifier.kind(
                name: accumulator.name,
                type: isWiFi ? "IEEE80211" : nil,
                hardware: nil
            )
            let ssid = isWiFi ? interface?.ssid() : nil
            let bssid = isWiFi ? interface?.bssid()?.uppercased() : nil
            let rssi = isWiFi ? Int(interface?.rssiValue() ?? 0) : nil
            let security = isWiFi ? securityLabel(interface?.security()) : nil
            return SystemInterface(
                bsdName: accumulator.name,
                displayName: displayName(for: kind, name: accumulator.name),
                kind: kind,
                isUp: accumulator.flags & UInt32(IFF_UP) != 0,
                isRunning: accumulator.flags & UInt32(IFF_RUNNING) != 0,
                isPrimary: accumulator.name == routes.primary,
                macAddress: scInfo[accumulator.name]?.mac ?? accumulator.macAddress,
                mtu: mtu(for: accumulator.name),
                linkSpeedMbps: accumulator.linkSpeedMbps,
                ipv4: accumulator.ipv4,
                ipv6: accumulator.ipv6,
                rxBytes: accumulator.rxBytes,
                txBytes: accumulator.txBytes,
                rxPackets: accumulator.rxPackets,
                txPackets: accumulator.txPackets,
                rxErrors: accumulator.rxErrors,
                txErrors: accumulator.txErrors,
                ssid: ssid,
                bssid: bssid,
                rssi: rssi == 0 ? nil : rssi,
                security: security,
                dnsServers: routes.dns,
                router: routes.router
            )
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.sortOrder < rhs.kind.sortOrder }
            return lhs.bsdName.localizedStandardCompare(rhs.bsdName) == .orderedAscending
        }

        return InterfacesReport(
            generatedAt: Date(),
            interfaces: interfaces,
            primaryInterface: routes.primary,
            dnsServers: routes.dns,
            router: routes.router
        )
    }

    // MARK: - Helpers

    private struct Accumulator {
        let name: String
        var flags: UInt32 = 0
        var macAddress: String?
        var linkSpeedMbps: Int?
        var ipv4: [InterfaceAddress] = []
        var ipv6: [InterfaceAddress] = []
        var rxBytes: UInt64 = 0
        var txBytes: UInt64 = 0
        var rxPackets: UInt64 = 0
        var txPackets: UInt64 = 0
        var rxErrors: UInt64 = 0
        var txErrors: UInt64 = 0
    }

    private static func linkLayerAddress(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        let link = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_dl.self)
        guard link.pointee.sdl_alen == 6 else { return nil }
        let offset = Int(link.pointee.sdl_nlen)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: link.pointee.sdl_data) { raw in
            guard offset + 6 <= raw.count else { return }
            bytes = Array(raw[offset..<(offset + 6)])
        }
        guard bytes.count == 6 else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_len)
        guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
    }

    private static func netmaskPrefix(_ mask: UnsafeMutablePointer<sockaddr>) -> Int? {
        guard mask.pointee.sa_family == UInt8(AF_INET) else { return nil }
        let address = UnsafeRawPointer(mask).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
        let value = UInt32(bigEndian: address.s_addr)
        return value.nonzeroBitCount
    }

    private static func mtu(for name: String) -> Int? {
        let socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else { return nil }
        defer { close(socketFD) }
        var request = ifreq()
        let bytes = Array(name.utf8.prefix(Int(IFNAMSIZ) - 1))
        withUnsafeMutableBytes(of: &request.ifr_name) { raw in
            raw.copyBytes(from: bytes)
        }
        // SIOCGIFMTU
        guard ioctl(socketFD, UInt(0xC0206933), &request) == 0 else { return nil }
        let value = request.ifr_ifru.ifru_mtu
        return value > 0 ? Int(value) : nil
    }

    private static func displayName(for kind: InterfaceKind, name: String) -> String {
        switch kind {
        case .wifi: return "Wi-Fi (\(name))"
        case .ethernet: return "Ethernet (\(name))"
        case .bridge: return "Bridge (\(name))"
        case .tunnel: return "VPN / Tunnel (\(name))"
        case .loopback: return "Loopback (\(name))"
        case .awdl: return "AWDL (\(name))"
        case .cellular: return "Cellular (\(name))"
        case .other: return name
        }
    }

    private static func securityLabel(_ security: CWSecurity?) -> String? {
        guard let security else { return nil }
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA Personal"
        case .wpa2Personal: return "WPA2 Personal"
        case .wpa3Personal: return "WPA3 Personal"
        case .wpa3Transition: return "WPA3 Transition"
        case .OWE: return "OWE"
        case .wpa2Enterprise: return "WPA2 Enterprise"
        case .wpa3Enterprise: return "WPA3 Enterprise"
        default: return "Secured"
        }
    }

    private static func systemRoutes() -> (primary: String?, router: String?, dns: [String]) {
        guard let store = SCDynamicStoreCreate(nil, "LanFi.Interfaces" as CFString, nil, nil) else {
            return (nil, nil, [])
        }
        func value(_ key: String) -> [String: Any]? {
            guard let raw = SCDynamicStoreCopyValue(store, key as CFString) else { return nil }
            return raw as? [String: Any]
        }
        let ipv4 = value("State:/Network/Global/IPv4")
        let dns = value("State:/Network/Global/DNS")
        let configuredDNS = dns?["ServerAddresses"] as? [String] ?? []
        return (
            ipv4?["PrimaryInterface"] as? String,
            ipv4?["Router"] as? String,
            configuredDNS.isEmpty ? resolvConfServers() : configuredDNS
        )
    }

    private static func systemConfigurationInterfaces() -> [String: (mac: String?, mtu: Int?)] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: (String?, Int?)] = [:]
        for interface in interfaces {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            let mac = SCNetworkInterfaceGetHardwareAddressString(interface) as String?
            result[bsdName] = (mac, nil)
        }
        return result
    }

    private static func resolvConfServers() -> [String] {
        guard let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else { return [] }
        let fromFile = content.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver") else { return nil }
            return trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).last.map(String.init)
        }
        if !fromFile.isEmpty { return fromFile }

        // Modern macOS often keeps /etc/resolv.conf empty; ask the resolver directly.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--dns"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            var servers: [String] = []
            for line in output.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("nameserver"), let colon = trimmed.lastIndex(of: ":") else { continue }
                let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !servers.contains(value) { servers.append(value) }
            }
            return servers
        } catch {
            return []
        }
    }
}
