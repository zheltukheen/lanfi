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
    /// Model/description published via UPnP or Bonjour.
    let model: String?
    /// Human-readable service labels advertised by the device.
    let services: [String]

    init(
        ip: String,
        mac: String?,
        vendor: String?,
        hostname: String?,
        openPorts: [UInt16],
        latencyMilliseconds: Double?,
        isGateway: Bool,
        isThisMac: Bool,
        isNew: Bool,
        model: String? = nil,
        services: [String] = []
    ) {
        self.ip = ip
        self.mac = mac
        self.vendor = vendor
        self.hostname = hostname
        self.openPorts = openPorts
        self.latencyMilliseconds = latencyMilliseconds
        self.isGateway = isGateway
        self.isThisMac = isThisMac
        self.isNew = isNew
        self.model = model
        self.services = services
    }

    var id: String { "\(ip)-\(mac ?? "")" }
    var displayName: String {
        if let hostname { return hostname }
        if isThisMac { return String(localized: "This Mac") }
        if isGateway { return String(localized: "Router") }
        return vendor ?? String(localized: "Unknown device")
    }

    /// A short "what is it" line for the inspector: advertised services first,
    /// then the open-port catalogue.
    var serviceSummary: [String] {
        var labels = services
        for port in openPorts {
            if let label = LANServiceCatalog.label(forPort: port), !labels.contains(label) {
                labels.append(label)
            }
        }
        return labels
    }

    var kindLabel: String {
        if isGateway { return String(localized: "Router / gateway") }
        if isThisMac { return String(localized: "This Mac") }
        let labels = serviceSummary
        if labels.contains(where: { $0.contains("Printer") || $0.contains("printing") }) {
            return String(localized: "Printer")
        }
        if labels.contains(where: {
            $0.contains("AirPlay") || $0.contains("Cast") || $0.contains("Plex") || $0.contains("Media")
        }) {
            return String(localized: "Media device")
        }
        if labels.contains(where: { $0.contains("HomeKit") || $0.contains("Matter") || $0.contains("Sonos") }) {
            return String(localized: "Smart home device")
        }
        if labels.contains(where: { $0.contains("SMB") || $0.contains("AFP") || $0.contains("file sharing") }) {
            return String(localized: "File server / NAS")
        }
        if openPorts.contains(22) || openPorts.contains(3389) {
            return String(localized: "Computer / server")
        }
        if !labels.isEmpty { return labels[0] }
        return String(localized: "Network device")
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
        advertisements: [String: LANAdvertisement] = [:],
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
            let advertisement = advertisements[ip]
            return LANDevice(
                ip: ip,
                mac: entry?.mac,
                vendor: vendor == "-" ? nil : vendor,
                hostname: advertisement?.name ?? hostnames[ip],
                openPorts: open,
                latencyMilliseconds: latencies.min() ?? responsiveHosts[ip],
                isGateway: ip == gateway,
                isThisMac: entry?.mac == thisMAC?.uppercased(),
                isNew: !knownMACs.isEmpty && !knownMACs.contains(key),
                model: advertisement?.model,
                services: advertisement?.services ?? []
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
    /// The ARP table was empty, so MAC/vendor/hostname are missing and the
    /// list came from the ICMP fallback sweep. Almost always means Local
    /// Network access is off for the app rather than an empty network.
    var localNetworkAccessLikelyDenied: Bool = false
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

// MARK: - Device information advertised on the LAN

/// Information a device publishes about itself through Bonjour, SSDP/UPnP or
/// reverse DNS. Every field is optional because most devices only expose a
/// subset; merging keeps the first non-empty value.
struct LANAdvertisement: Equatable, Sendable {
    var name: String?
    var model: String?
    var manufacturer: String?
    var services: [String]

    init(
        name: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil,
        services: [String] = []
    ) {
        self.name = name
        self.model = model
        self.manufacturer = manufacturer
        self.services = services
    }

    var isEmpty: Bool {
        name == nil && model == nil && manufacturer == nil && services.isEmpty
    }

    func merged(with other: LANAdvertisement) -> LANAdvertisement {
        LANAdvertisement(
            name: Self.preferred(name, other.name),
            model: Self.preferred(model, other.model),
            manufacturer: Self.preferred(manufacturer, other.manufacturer),
            services: Array(Set(services + other.services)).sorted()
        )
    }

    private static func preferred(_ first: String?, _ second: String?) -> String? {
        if let first, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return first
        }
        guard let second, !second.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return second
    }
}

enum LANServiceCatalog {
    private static let portLabels: [UInt16: String] = [
        22: "SSH",
        23: "Telnet",
        53: "DNS",
        80: "Web",
        139: "SMB",
        443: "Secure web",
        445: "SMB file sharing",
        515: "Printer",
        548: "AFP file sharing",
        631: "IPP printing",
        3000: "Web app",
        3389: "Remote desktop",
        5000: "Web app",
        7000: "AirPlay",
        8000: "Web app",
        8080: "Web app",
        8443: "Secure web app",
        9100: "Raw printing",
        32400: "Plex",
        62078: "iPhone sync",
    ]

    static func label(forPort port: UInt16) -> String? {
        portLabels[port]
    }

    static func label(forBonjourType type: String) -> String? {
        let normalized = type.lowercased()
        let labels: [(String, String)] = [
            ("_airplay._tcp", "AirPlay"),
            ("_raop._tcp", "AirPlay audio"),
            ("_googlecast._tcp", "Google Cast"),
            ("_spotify-connect._tcp", "Spotify Connect"),
            ("_sonos._tcp", "Sonos"),
            ("_ipp._tcp", "IPP printing"),
            ("_ipps._tcp", "IPP printing"),
            ("_printer._tcp", "Printer"),
            ("_pdl-datastream._tcp", "Printer"),
            ("_smb._tcp", "SMB file sharing"),
            ("_afpovertcp._tcp", "AFP file sharing"),
            ("_ssh._tcp", "SSH"),
            ("_sftp-ssh._tcp", "SFTP"),
            ("_http._tcp", "Web interface"),
            ("_https._tcp", "Secure web interface"),
            ("_workstation._tcp", "Workstation"),
            ("_device-info._tcp", "Device info"),
            ("_hap._tcp", "HomeKit"),
            ("_companion-link._tcp", "Apple Continuity"),
            ("_sleep-proxy._udp", "Sleep proxy"),
            ("_matter._tcp", "Matter"),
            ("_homekit._tcp", "HomeKit"),
        ]
        return labels.first { normalized.contains($0.0) }?.1
    }
}

/// One SSDP reply. Header names are case-insensitive in the wire format.
struct SSDPResponse: Equatable, Sendable {
    let sourceIP: String
    let location: String?
    let server: String?
    let usn: String?
    let searchTarget: String?
}

enum SSDPParser {
    static func parseResponse(_ text: String, sourceIP: String) -> SSDPResponse? {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != "HTTP/1.1 200 OK", !trimmed.isEmpty,
                let colon = trimmed.firstIndex(of: ":")
            else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            headers[key] = value
        }
        guard !headers.isEmpty else { return nil }
        return SSDPResponse(
            sourceIP: sourceIP,
            location: headers["location"],
            server: headers["server"],
            usn: headers["usn"],
            searchTarget: headers["st"]
        )
    }
}

/// Minimal UPnP device-description reader. Full XML parsing is unnecessary:
/// the fields we show live in simple, uniquely named leaf elements.
enum UPnPDescriptionParser {
    static func parse(_ xml: String) -> LANAdvertisement {
        let name = value(of: "friendlyName", in: xml)
        let manufacturer = value(of: "manufacturer", in: xml)
        let model =
            value(of: "modelName", in: xml)
            ?? value(of: "modelDescription", in: xml)
        var services: [String] = []
        if let deviceType = value(of: "deviceType", in: xml) {
            let leaf = deviceType.split(separator: ":").dropLast().last.map(String.init)
            if let leaf, !leaf.isEmpty {
                services.append(Self.humanize(leaf))
            }
        }
        if services.isEmpty {
            services.append("UPnP")
        }
        return LANAdvertisement(
            name: name,
            model: model,
            manufacturer: manufacturer,
            services: services
        )
    }

    private static func value(of tag: String, in xml: String) -> String? {
        for openTag in ["<\(tag)>", "<\(tag) ", "<ns:\(tag)>", "<ns:\(tag) "] {
            guard let start = xml.range(of: openTag, options: .caseInsensitive) else {
                continue
            }
            let remainder = xml[start.upperBound...]
            guard let close = remainder.range(of: "</", options: .caseInsensitive),
                let end = remainder.range(of: ">", options: .caseInsensitive)
            else { continue }
            let content = remainder[..<close.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty, end.lowerBound >= close.lowerBound else { continue }
            return decodeEntities(content)
        }
        return nil
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }

    private static func humanize(_ value: String) -> String {
        switch value.lowercased() {
        case "mediarenderer": return "Media renderer"
        case "mediaserver": return "Media server"
        case "internetgatewaydevice": return "Router"
        case "printer": return "Printer"
        case "basic": return "UPnP device"
        default:
            return
                value
                .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
    }
}
