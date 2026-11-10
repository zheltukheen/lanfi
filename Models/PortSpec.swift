import Foundation

enum PortSpecError: Error, Equatable {
    case empty
    case invalid(String)
    case outOfRange(Int)
    case tooMany(Int)
}

enum PortPreset: String, CaseIterable, Identifiable, Sendable {
    case common
    case web
    case mail
    case remote
    case databases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: return "Common"
        case .web: return "Web"
        case .mail: return "Mail"
        case .remote: return "Remote"
        case .databases: return "Databases"
        }
    }

    var ports: [UInt16] {
        switch self {
        case .common:
            return [
                21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 587, 993, 3306, 3389, 5432, 6379,
                8080, 8443, 9090,
            ]
        case .web:
            return [80, 443, 3000, 5000, 8000, 8080, 8443, 9000]
        case .mail:
            return [25, 110, 143, 465, 587, 993, 995]
        case .remote:
            return [22, 23, 3389, 5900]
        case .databases:
            return [1433, 1521, 3306, 5432, 6379, 27017]
        }
    }
}

enum PortSpec {
    /// Guard against a typo turning into a 65k-connection sweep.
    static let maximumPorts = 4096

    static func parse(_ raw: String) throws -> [UInt16] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PortSpecError.empty }

        var ports = Set<UInt16>()
        for token in trimmed.split(separator: ",") {
            let piece = token.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { throw PortSpecError.invalid(String(token)) }
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
            if bounds.count == 2 {
                guard let start = Int(bounds[0]), let end = Int(bounds[1]) else {
                    throw PortSpecError.invalid(piece)
                }
                guard (1...65535).contains(start), (1...65535).contains(end) else {
                    throw PortSpecError.outOfRange(start < 1 || start > 65535 ? start : end)
                }
                guard start <= end else { throw PortSpecError.invalid(piece) }
                for port in start...end {
                    ports.insert(UInt16(port))
                    if ports.count > maximumPorts { throw PortSpecError.tooMany(maximumPorts) }
                }
            } else if bounds.count == 1 {
                guard let value = Int(piece) else { throw PortSpecError.invalid(piece) }
                guard (1...65535).contains(value) else { throw PortSpecError.outOfRange(value) }
                ports.insert(UInt16(value))
            } else {
                throw PortSpecError.invalid(piece)
            }
        }
        let sorted = ports.sorted()
        guard sorted.count <= maximumPorts else { throw PortSpecError.tooMany(maximumPorts) }
        return sorted
    }
}

enum PortServices {
    private static let names: [UInt16: String] = [
        20: "FTP Data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP", 53: "DNS",
        67: "DHCP", 68: "DHCP", 69: "TFTP", 80: "HTTP", 110: "POP3", 111: "RPC",
        123: "NTP", 135: "MS RPC", 137: "NetBIOS", 138: "NetBIOS", 139: "NetBIOS",
        143: "IMAP", 161: "SNMP", 162: "SNMP Trap", 389: "LDAP", 443: "HTTPS",
        445: "SMB", 465: "SMTPS", 500: "IKE", 514: "Syslog", 515: "LPD",
        548: "AFP", 587: "Submission", 631: "IPP", 636: "LDAPS", 873: "rsync",
        993: "IMAPS", 995: "POP3S", 1194: "OpenVPN", 1433: "MSSQL", 1521: "Oracle",
        1723: "PPTP", 1883: "MQTT", 2049: "NFS", 2181: "ZooKeeper", 3000: "HTTP Alt",
        3306: "MySQL", 3389: "RDP", 5000: "HTTP Alt", 5432: "PostgreSQL",
        5672: "AMQP", 5900: "VNC", 6379: "Redis", 7000: "AirPlay", 8000: "HTTP Alt",
        8080: "HTTP Alt", 8443: "HTTPS Alt", 8883: "MQTT TLS", 9000: "HTTP Alt",
        9090: "Prometheus", 9200: "Elasticsearch", 27017: "MongoDB",
    ]

    static func name(for port: UInt16) -> String? {
        names[port]
    }
}
