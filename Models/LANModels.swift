import Foundation

struct ARPEntry: Equatable, Sendable {
    let ip: String
    let mac: String
}

enum ARPParser {
    /// Parses `/usr/sbin/arp -an` lines such as
    /// `? (192.168.1.1) at 3c:22:fb:11:22:33 on en0 ifscope [ethernet]`.
    static func parse(_ output: String) -> [ARPEntry] {
        var entries: [ARPEntry] = []
        var seen = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) {
            guard let open = line.firstIndex(of: "("),
                let close = line.firstIndex(of: ")"),
                open < close,
                let at = line.range(of: " at ")
            else { continue }
            let ip = String(line[line.index(after: open)..<close])
            guard IPv4Address(ip) != nil else { continue }
            let rest = line[at.upperBound...]
            guard let token = rest.split(whereSeparator: \.isWhitespace).first,
                let mac = normalizedMAC(String(token)),
                mac != "FF:FF:FF:FF:FF:FF", mac != "00:00:00:00:00:00"
            else { continue }
            let key = "\(ip)-\(mac)"
            if seen.insert(key).inserted {
                entries.append(ARPEntry(ip: ip, mac: mac))
            }
        }
        return entries
    }

    static func isMAC(_ value: String) -> Bool {
        normalizedMAC(value) != nil
    }

    /// `arp` prints octets without leading zeros (`0:11:32:30:62:49`), so the
    /// canonical form pads every octet to two hex digits.
    static func normalizedMAC(_ value: String) -> String? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var octets: [String] = []
        for part in parts {
            guard (1...2).contains(part.count), let byte = UInt8(part, radix: 16) else {
                return nil
            }
            octets.append(String(format: "%02X", byte))
        }
        return octets.joined(separator: ":")
    }
}

enum LANSubnet {
    /// Host addresses in a CIDR block, excluding network and broadcast where
    /// they exist. Capped so a /8 cannot turn into a 16-million-probe sweep.
    static func hosts(address: String, prefixLength: Int, limit: Int = 254) -> [String] {
        guard let address = IPv4Address(address),
            let subnet = SubnetCalculator.subnet(address: address, prefixLength: prefixLength),
            let first = subnet.firstUsable?.value,
            let last = subnet.lastUsable?.value
        else { return [] }

        var result: [String] = []
        var current = first
        while current <= last, result.count < max(1, limit) {
            result.append(IPv4Address(current).description)
            if current == UInt32.max { break }
            current += 1
        }
        return result
    }
}

struct LANDevice: Identifiable, Equatable, Sendable {
    let ip: String
    let mac: String?
    let vendor: String?
    let hostname: String?
    let openPorts: [UInt16]
    let latencyMilliseconds: Double?
    let isGateway: Bool
    let isThisMac: Bool
    let isNew: Bool

    var id: String { "\(ip)-\(mac ?? "")" }
    var displayName: String {
        if let hostname { return hostname }
        if isThisMac { return "This Mac" }
        if isGateway { return "Router" }
        return vendor ?? "Unknown device"
    }
}

enum LANDeviceAssembler {
    static func assemble(
        entries: [ARPEntry],
        responsiveHosts: [String: Double] = [:],
        hostnames: [String: String],
        probes: [String: [PortScanResult]],
        gateway: String?,
        thisMAC: String?,
        knownMACs: Set<String>,
        vendorFor: (String) -> String = OUIParser.vendor
    ) -> [LANDevice] {
        var arpByIP: [String: ARPEntry] = [:]
        for entry in entries where ARPParser.isMAC(entry.mac) {
            arpByIP[entry.ip] = entry
        }
        let ips = Set(arpByIP.keys).union(responsiveHosts.keys)

        return ips.map { ip -> LANDevice in
            let entry = arpByIP[ip]
            let results = probes[ip] ?? []
            let open = results.filter { $0.state == .open }.map(\.port).sorted()
            let latencies = results.compactMap(\.responseMilliseconds)
            let vendor = entry.map { vendorFor($0.mac) }
            let key = entry?.mac ?? ip
            return LANDevice(
                ip: ip,
                mac: entry?.mac,
                vendor: vendor == "-" ? nil : vendor,
                hostname: hostnames[ip],
                openPorts: open,
                latencyMilliseconds: latencies.min() ?? responsiveHosts[ip],
                isGateway: ip == gateway,
                isThisMac: entry?.mac == thisMAC?.uppercased(),
                isNew: !knownMACs.isEmpty && !knownMACs.contains(key)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isGateway != rhs.isGateway { return lhs.isGateway }
            return (IPv4Address(lhs.ip)?.value ?? 0) < (IPv4Address(rhs.ip)?.value ?? 0)
        }
    }
}

enum LANGuard {
    static func newDevices(in devices: [LANDevice], knownMACs: Set<String>) -> [LANDevice] {
        devices.filter { device in
            let key = device.mac ?? device.ip
            return !knownMACs.contains(key)
        }
    }
}

struct LANScanResult: Equatable, Sendable {
    let interfaceName: String
    let subnet: String
    let gateway: String?
    let devices: [LANDevice]
    let scannedAt: Date
}

final class LANGuardStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = directory ?? support.appendingPathComponent("LanFi", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("lan-guard.json")
    }

    func load() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
            let macs = try? decoder.decode([String].self, from: data)
        else { return [] }
        return Set(macs.map { $0.uppercased() })
    }

    func save(_ macs: Set<String>) {
        guard let data = try? encoder.encode(macs.sorted()) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
