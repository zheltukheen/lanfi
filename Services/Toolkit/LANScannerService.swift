import Darwin
import Foundation

enum LANScannerError: Error, Equatable, LocalizedError {
    case noInterface
    case arpUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noInterface:
            return "No active Wi-Fi or Ethernet interface with an IPv4 address."
        case .arpUnavailable(let detail):
            return "The ARP table could not be read: \(detail)"
        }
    }
}

struct LANScannerService {
    var probePorts: [UInt16] = [
        22, 80, 139, 443, 445, 548, 631, 3_389, 5_000, 7_000, 8_080, 9_100, 62_078,
    ]

    func scan(knownMACs: Set<String>, guardEnabled: Bool) async throws -> LANScanResult {
        let report = SystemInterfaceScanner.scan()
        let candidates = report.interfaces.filter { item in
            (item.kind == .wifi || item.kind == .ethernet)
                && item.primaryIPv4 != nil
                && item.ipv4.first?.prefixLength != nil
        }
        guard let interface = candidates.first(where: \.isPrimary) ?? candidates.first,
            let address = interface.primaryIPv4,
            let prefix = interface.ipv4.first?.prefixLength
        else { throw LANScannerError.noInterface }

        let hosts = LANSubnet.hosts(address: address, prefixLength: prefix)
        guard !hosts.isEmpty else { throw LANScannerError.noInterface }
        // Ask for Local Network access in-process first: reading `arp` through a
        // child process does not trigger the macOS prompt for this app.
        LocalNetworkAccess.request()
        ARPSweeper.nudge(hosts: hosts)

        // Run the independent discovery passes together instead of waiting for
        // each one in turn: ICMP sweep, Bonjour and SSDP all overlap.
        async let bonjourTask = BonjourDiscovery.advertisements(timeout: 1.0)
        async let ssdpTask = SSDPDiscovery.advertisements(timeout: 1.0)
        let responsive = await sweep(hosts)

        var entries = readARPHostEntries(hosts: hosts)
        if entries.isEmpty {
            // Give the ARP cache a second chance after the sweep; some routers
            // answer ICMP before they answer the UDP nudge.
            ARPSweeper.nudge(hosts: hosts)
            try? await Task.sleep(nanoseconds: 300_000_000)
            entries = readARPHostEntries(hosts: hosts)
        }

        let resolvedGateway = gateway(for: interface.bsdName) ?? report.router
        let probeHosts = Array(Set(entries.map(\.ip)).union(responsive.keys))
            .sorted { (IPv4Address($0)?.value ?? 0) < (IPv4Address($1)?.value ?? 0) }

        // PTR names and TCP probes are independent of the ARP result, so a
        // denied ARP table still produces responsive addresses with names.
        async let reverseTask = ReverseDNS.names(hosts: probeHosts)
        let probes = await probe(probeHosts)
        let banners = await fetchBanners(from: probes)
        let bonjour = await bonjourTask
        let ssdp = await ssdpTask
        let reversed = await reverseTask

        var advertisements = bonjour
        for (ip, advertisement) in ssdp {
            advertisements[ip] = advertisements[ip]?.merged(with: advertisement) ?? advertisement
        }
        for (ip, name) in reversed {
            let advertisement = LANAdvertisement(name: name)
            advertisements[ip] = advertisements[ip]?.merged(with: advertisement) ?? advertisement
        }

        let devices = LANDeviceAssembler.assemble(
            entries: entries,
            responsiveHosts: responsive,
            hostnames: [:],
            probes: probes,
            gateway: resolvedGateway,
            thisMAC: interface.macAddress,
            knownMACs: guardEnabled ? knownMACs : [],
            advertisements: advertisements,
            banners: banners
        )
        return LANScanResult(
            interfaceName: interface.bsdName,
            subnet: "\(address)/\(prefix)",
            gateway: resolvedGateway,
            devices: devices,
            scannedAt: Date(),
            localNetworkAccessLikelyDenied: entries.isEmpty
        )
    }

    private func readARPHostEntries(hosts: [String]) -> [ARPEntry] {
        guard let output = try? ARPTableReader.read() else { return [] }
        let hostSet = Set(hosts)
        return ARPParser.parse(output).filter { hostSet.contains($0.ip) }
    }

    /// The global router can be a VPN. For a LAN scan, read the default route
    /// scoped to the chosen interface so the gateway is the Wi-Fi/Ethernet one.
    private func gateway(for interfaceName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "-ifscope", interfaceName, "default"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let text = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "gateway"
            else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return IPv4Address(value) == nil ? nil : value
        }
        return nil
    }

    /// Probes every host/port pair through one sliding window. A dropped or
    /// slow port only occupies its slot for the probe timeout; the rest keep
    /// flowing, and no per-host batch waits for its slowest member.
    private func probe(_ hosts: [String]) async -> [String: [PortScanResult]] {
        let pairs = hosts.flatMap { host in probePorts.map { (host, $0) } }
        guard !pairs.isEmpty else { return [:] }
        var results: [String: [PortScanResult]] = [:]
        let probe = TCPPortProbe()
        let timeout: TimeInterval = 0.55
        let width = min(96, pairs.count)

        await withTaskGroup(of: (String, PortScanResult).self) { group in
            var iterator = pairs.makeIterator()
            for _ in 0..<width {
                guard let pair = iterator.next() else { break }
                group.addTask {
                    let result = await probe.probe(
                        host: pair.0, port: pair.1, timeout: timeout)
                    return (pair.0, result)
                }
            }
            while let (host, result) = await group.next() {
                results[host, default: []].append(result)
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let pair = iterator.next() {
                    group.addTask {
                        let result = await probe.probe(
                            host: pair.0, port: pair.1, timeout: timeout)
                        return (pair.0, result)
                    }
                }
            }
        }
        return results.mapValues { $0.sorted { $0.port < $1.port } }
    }

    /// Reads the version banner on the most useful open ports. This runs after
    /// the TCP probe so it only touches ports that already answered, and caps
    /// both ports per host and concurrency to keep the scan fast.
    private func fetchBanners(from probes: [String: [PortScanResult]])
        async -> [String: [UInt16: String]]
    {
        let candidates: [(String, UInt16)] = probes.flatMap { host, results in
            results
                .filter { $0.state == .open && Self.bannerPorts.contains($0.port) }
                .map(\.port)
                .sorted()
                .prefix(2)
                .map { (host, $0) }
        }
        guard !candidates.isEmpty else { return [:] }

        var banners: [String: [UInt16: String]] = [:]
        await withTaskGroup(of: (String, UInt16, String?).self) { group in
            var iterator = candidates.makeIterator()
            let width = min(16, candidates.count)
            for _ in 0..<width {
                guard let pair = iterator.next() else { break }
                group.addTask {
                    let banner = await ServiceBannerProbe().probe(
                        host: pair.0, port: pair.1, timeout: 0.9)
                    return (pair.0, pair.1, banner)
                }
            }
            while let (host, port, banner) = await group.next() {
                if let banner { banners[host, default: [:]][port] = banner }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let pair = iterator.next() {
                    group.addTask {
                        let banner = await ServiceBannerProbe().probe(
                            host: pair.0, port: pair.1, timeout: 0.9)
                        return (pair.0, pair.1, banner)
                    }
                }
            }
        }
        return banners
    }

    private static let bannerPorts: Set<UInt16> = [21, 22, 25, 80, 5000, 8080, 8000]

    private func sweep(_ hosts: [String]) async -> [String: Double] {
        var responsive: [String: Double] = [:]
        let width = min(128, hosts.count)
        guard width > 0 else { return responsive }

        await withTaskGroup(of: (String, Double?).self) { group in
            var iterator = hosts.makeIterator()
            for _ in 0..<width {
                guard let host = iterator.next() else { break }
                group.addTask {
                    let sample = await ICMPPingProbe().probe(
                        host: host, sequence: 1, timeout: 0.45)
                    return (host, sample.rttMilliseconds)
                }
            }
            while let (host, rtt) = await group.next() {
                if let rtt { responsive[host] = rtt }
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let host = iterator.next() {
                    group.addTask {
                        let sample = await ICMPPingProbe().probe(
                            host: host, sequence: 1, timeout: 0.45)
                        return (host, sample.rttMilliseconds)
                    }
                }
            }
        }
        return responsive
    }
}

private enum ARPSweeper {
    /// Sends a single UDP datagram to each host so the kernel resolves its
    /// link-layer address and fills the ARP table. No reply is needed.
    static func nudge(hosts: [String]) {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let payload = [UInt8](repeating: 0, count: 8)
        for host in hosts {
            var destination = sockaddr_in()
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_port = UInt16(9).bigEndian
            guard inet_pton(AF_INET, host, &destination.sin_addr) == 1 else { continue }
            _ = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(
                        descriptor, payload, payload.count, 0, address,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

enum ARPTableReader {
    static func read() throws -> String {
        let executable = "/usr/sbin/arp"
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw LANScannerError.arpUnavailable("arp is unavailable")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-an"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw LANScannerError.arpUnavailable(error.localizedDescription)
        }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let text = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw LANScannerError.arpUnavailable(text)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - SSDP / UPnP

/// Discovers devices that answer SSDP (media players, TVs, routers, printers,
/// NAS boxes) and reads their UPnP description for a friendly name and model.
enum SSDPDiscovery {
    static func advertisements(timeout: TimeInterval = 1.0) async -> [String: LANAdvertisement] {
        let responses = await Task.detached(priority: .utility) {
            receive(timeout: timeout)
        }.value
        guard !responses.isEmpty else { return [:] }

        // Deduplicate by USN/location; one device often sends several replies.
        var unique: [String: SSDPResponse] = [:]
        for response in responses {
            let key = response.usn ?? response.location ?? response.sourceIP
            if unique[key] == nil { unique[key] = response }
        }
        let selected = Array(unique.values.prefix(24))

        var advertisements: [String: LANAdvertisement] = [:]
        await withTaskGroup(of: (String, LANAdvertisement).self) { group in
            var iterator = selected.makeIterator()
            let width = min(8, selected.count)
            for _ in 0..<width {
                guard let response = iterator.next() else { break }
                group.addTask {
                    (response.sourceIP, await fetchAdvertisement(for: response))
                }
            }
            while let (ip, advertisement) = await group.next() {
                guard !advertisement.isEmpty else { continue }
                advertisements[ip] = advertisements[ip]?.merged(with: advertisement) ?? advertisement
                if let response = iterator.next() {
                    group.addTask {
                        (response.sourceIP, await fetchAdvertisement(for: response))
                    }
                }
            }
        }
        return advertisements
    }

    private static func fetchAdvertisement(for response: SSDPResponse) async -> LANAdvertisement {
        var advertisement = LANAdvertisement(services: ["UPnP"])
        if let location = response.location, let url = URL(string: location),
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
        {
            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5
            request.setValue("application/xml, text/xml, */*", forHTTPHeaderField: "Accept")
            if let (data, _) = try? await URLSession.shared.data(for: request),
                let text = String(data: data, encoding: .utf8)
            {
                advertisement = UPnPDescriptionParser.parse(text)
            }
        }
        if let server = response.server, !server.isEmpty {
            // Example: "Linux/3.14 UPnP/1.0 MiniDLNA/1.0". The last token is
            // the product that actually speaks UPnP; earlier tokens are the OS
            // and protocol version.
            let tokens = server.split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
            if tokens.count >= 2 {
                let product = tokens[tokens.count - 2]
                let productVersion = tokens[tokens.count - 1]
                if advertisement.model == nil, product != "UPnP" {
                    advertisement.model = product
                }
                if advertisement.version == nil, productVersion.first?.isNumber == true {
                    advertisement.version = productVersion
                }
            }
            if advertisement.name == nil, let first = tokens.first, !first.isEmpty {
                advertisement.name = first
            }
        }
        return advertisement
    }

    private static func receive(timeout: TimeInterval) -> [SSDPResponse] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(
            descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size))

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = UInt16(1900).bigEndian
        guard inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr) == 1 else {
            return []
        }
        var ttl: UInt8 = 2
        setsockopt(
            descriptor, IPPROTO_IP, IP_MULTICAST_TTL, &ttl,
            socklen_t(MemoryLayout<UInt8>.size))

        let request = Data(
            """
            M-SEARCH * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            MAN: "ssdp:discover"\r
            MX: 1\r
            ST: ssdp:all\r
            \r
            """.utf8)
        let bytes = [UInt8](request)
        for _ in 0..<2 {
            _ = withUnsafePointer(to: &destination) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    sendto(
                        descriptor, bytes, bytes.count, 0, address,
                        socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        let deadline = Date().addingTimeInterval(max(0.3, timeout))
        var responses: [SSDPResponse] = []
        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 8_192)
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let received = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(
                        descriptor, &buffer, buffer.count, 0, address, &sourceLength)
                }
            }
            if received <= 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                break
            }
            var address = source.sin_addr
            var nameBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &nameBuffer, socklen_t(nameBuffer.count)) != nil
            else { continue }
            let sourceIP = String(cString: nameBuffer)
            let text = String(decoding: buffer[0..<received], as: UTF8.self)
            if let response = SSDPParser.parseResponse(text, sourceIP: sourceIP) {
                responses.append(response)
            }
        }
        return responses
    }
}

// MARK: - Reverse DNS

/// PTR lookups for the addresses that answered. Host names are a strong
/// identity hint on managed networks and cost one short UDP query per host.
enum ReverseDNS {
    static func names(hosts: [String], timeout: TimeInterval = 0.6) async -> [String: String] {
        guard !hosts.isEmpty else { return [:] }
        var names: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = hosts.makeIterator()
            let width = min(8, hosts.count)
            for _ in 0..<width {
                guard let host = iterator.next() else { break }
                group.addTask { (host, await lookupName(for: host, timeout: timeout)) }
            }
            while let (host, name) = await group.next() {
                if let name { names[host] = name }
                if let host = iterator.next() {
                    group.addTask { (host, await lookupName(for: host, timeout: timeout)) }
                }
            }
        }
        return names
    }

    private static func lookupName(for host: String, timeout: TimeInterval) async -> String? {
        guard IPv4Address(host) != nil else { return nil }
        let reversed = host.split(separator: ".").reversed().joined(separator: ".") + ".in-addr.arpa"
        guard
            let result = try? await UDPDNSClient().lookup(
                host: reversed, type: .ptr, resolver: .system, timeout: timeout),
            let value = result.records.first?.value.trimmingCharacters(
                in: CharacterSet(charactersIn: ".")
            ),
            !value.isEmpty
        else { return nil }
        return value
    }
}
