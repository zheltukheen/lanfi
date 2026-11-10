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
    var probePorts: [UInt16] = [22, 80, 443, 445, 5_000, 7_000, 8_080, 3_389]

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
        ARPSweeper.nudge(hosts: hosts)
        try? await Task.sleep(nanoseconds: 900_000_000)

        let arpOutput = try ARPTableReader.read()
        let hostSet = Set(hosts)
        let parsed = ARPParser.parse(arpOutput)
        let entries = parsed.filter { hostSet.contains($0.ip) }
        let resolvedGateway = gateway(for: interface.bsdName) ?? report.router

        // macOS can hide the ARP table from a non-privileged child process
        // until Local Network access is granted. When it is empty, fall back to
        // an ICMP/TCP sweep so the scanner still finds devices; MAC/vendor are
        // filled in when ARP is available.
        let responsive = entries.isEmpty ? await sweep(hosts) : [:]
        let probeHosts = entries.isEmpty ? Array(responsive.keys) : entries.map(\.ip)
        let hostnames = await BonjourDiscovery.names(timeout: 2)
        let probes = await probe(probeHosts)

        let devices = LANDeviceAssembler.assemble(
            entries: entries,
            responsiveHosts: responsive,
            hostnames: hostnames,
            probes: probes,
            gateway: resolvedGateway,
            thisMAC: interface.macAddress,
            knownMACs: guardEnabled ? knownMACs : []
        )
        return LANScanResult(
            interfaceName: interface.bsdName,
            subnet: "\(address)/\(prefix)",
            gateway: resolvedGateway,
            devices: devices,
            scannedAt: Date()
        )
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

    private func probe(_ hosts: [String]) async -> [String: [PortScanResult]] {
        guard !hosts.isEmpty else { return [:] }
        var results: [String: [PortScanResult]] = [:]
        let batchSize = 8

        for start in stride(from: 0, to: hosts.count, by: batchSize) {
            if Task.isCancelled { break }
            let batch = Array(hosts[start..<min(start + batchSize, hosts.count)])
            await withTaskGroup(of: (String, [PortScanResult]).self) { group in
                for host in batch {
                    group.addTask {
                        let scan = await PortScanner(probe: TCPPortProbe()).scan(
                            host: host,
                            ports: probePorts,
                            timeout: 0.8,
                            concurrency: 6
                        )
                        return (host, scan)
                    }
                }
                for await (ip, scan) in group {
                    results[ip] = scan
                }
            }
        }
        return results
    }

    private func sweep(_ hosts: [String]) async -> [String: Double] {
        var responsive: [String: Double] = [:]
        let batchSize = 32
        for start in stride(from: 0, to: hosts.count, by: batchSize) {
            if Task.isCancelled { break }
            let batch = Array(hosts[start..<min(start + batchSize, hosts.count)])
            await withTaskGroup(of: (String, Double?).self) { group in
                for host in batch {
                    group.addTask {
                        let sample = await ICMPPingProbe().probe(
                            host: host, sequence: 1, timeout: 0.6)
                        return (host, sample.rttMilliseconds)
                    }
                }
                for await (host, rtt) in group {
                    if let rtt { responsive[host] = rtt }
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
