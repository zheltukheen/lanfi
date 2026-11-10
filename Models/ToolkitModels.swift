import Foundation

// MARK: - Targets

/// A host and optional port parsed from a free-form tool field.
struct ToolTarget: Equatable, Sendable {
    let host: String
    let port: UInt16?

    var display: String {
        let renderedHost = host.contains(":") ? "[\(host)]" : host
        guard let port else { return renderedHost }
        return "\(renderedHost):\(port)"
    }

    /// Accepts `host`, `host:port`, `scheme://host[:port][/path]` and
    /// `[ipv6]:port`. Returns nil for empty or obviously malformed input.
    static func parse(_ raw: String, defaultPort: UInt16? = nil) -> ToolTarget? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }

        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            let host = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            guard !host.isEmpty else { return nil }
            if rest.isEmpty { return ToolTarget(host: host, port: defaultPort) }
            guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()), port > 0 else {
                return nil
            }
            return ToolTarget(host: host, port: port)
        }

        let colonCount = value.reduce(into: 0) { count, character in
            if character == ":" { count += 1 }
        }
        if colonCount == 1, let colon = value.lastIndex(of: ":") {
            let host = String(value[..<colon])
            let portText = String(value[value.index(after: colon)...])
            guard !host.isEmpty, let port = UInt16(portText), port > 0 else { return nil }
            return ToolTarget(host: host, port: port)
        }
        if colonCount > 1 {
            return ToolTarget(host: value, port: defaultPort)
        }
        return ToolTarget(host: value, port: defaultPort)
    }
}

// MARK: - Ping

enum PingTransport: String, CaseIterable, Identifiable, Sendable {
    case icmp
    case tcp

    var id: String { rawValue }
    var title: String { self == .icmp ? "ICMP" : "TCP" }
}

struct PingSample: Identifiable, Equatable, Sendable {
    let sequence: Int
    let rttMilliseconds: Double?
    let at: Date
    let error: String?

    var id: Int { sequence }
    var succeeded: Bool { rttMilliseconds != nil }

    init(sequence: Int, rttMilliseconds: Double?, at: Date = Date(), error: String? = nil) {
        self.sequence = sequence
        self.rttMilliseconds = rttMilliseconds
        self.at = at
        self.error = error
    }
}

struct PingStatistics: Equatable, Sendable {
    let host: String
    let samples: [PingSample]

    init(host: String, samples: [PingSample]) {
        self.host = host
        self.samples = samples
    }

    var transmitted: Int { samples.count }
    var received: Int { samples.filter(\.succeeded).count }

    var packetLossPercent: Double {
        guard transmitted > 0 else { return 0 }
        return Double(transmitted - received) / Double(transmitted) * 100
    }

    var rttValues: [Double] { samples.compactMap(\.rttMilliseconds) }

    var minMilliseconds: Double? { rttValues.min() }
    var maxMilliseconds: Double? { rttValues.max() }

    var averageMilliseconds: Double? {
        guard !rttValues.isEmpty else { return nil }
        return rttValues.reduce(0, +) / Double(rttValues.count)
    }

    var standardDeviationMilliseconds: Double? {
        guard rttValues.count > 1, let average = averageMilliseconds else { return nil }
        let variance = rttValues.reduce(0) { $0 + pow($1 - average, 2) } / Double(rttValues.count)
        return sqrt(variance)
    }

    /// Mean absolute difference between consecutive replies — the jitter figure
    /// Netutilus shows next to loss.
    var jitterMilliseconds: Double? {
        guard rttValues.count > 1 else { return nil }
        var total = 0.0
        for index in 1..<rttValues.count {
            total += abs(rttValues[index] - rttValues[index - 1])
        }
        return total / Double(rttValues.count - 1)
    }
}

// MARK: - DNS

enum DNSRecordType: UInt16, CaseIterable, Identifiable, Sendable {
    case a = 1
    case ns = 2
    case cname = 5
    case soa = 6
    case ptr = 12
    case mx = 15
    case txt = 16
    case aaaa = 28
    case srv = 33
    case caa = 257

    var id: UInt16 { rawValue }

    var label: String {
        switch self {
        case .a: return String(localized: "A")
        case .ns: return String(localized: "NS")
        case .cname: return String(localized: "CNAME")
        case .soa: return String(localized: "SOA")
        case .ptr: return String(localized: "PTR")
        case .mx: return String(localized: "MX")
        case .txt: return String(localized: "TXT")
        case .aaaa: return String(localized: "AAAA")
        case .srv: return String(localized: "SRV")
        case .caa: return String(localized: "CAA")
        }
    }

    static func fromLabel(_ label: String) -> DNSRecordType? {
        let upper = label.uppercased()
        return allCases.first { $0.label == upper }
    }
}

struct DNSRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let type: DNSRecordType
    let ttl: UInt32
    let priority: UInt16?
    let value: String

    init(
        id: UUID = UUID(),
        name: String,
        type: DNSRecordType,
        ttl: UInt32,
        priority: UInt16? = nil,
        value: String
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.ttl = ttl
        self.priority = priority
        self.value = value
    }
}

struct DNSLookupResult: Equatable, Sendable {
    let host: String
    let resolver: String
    let records: [DNSRecord]
    let milliseconds: Int
}

struct DNSResolver: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let address: String?

    static let system = DNSResolver(id: "system", name: "System", address: nil)
    static let cloudflare = DNSResolver(id: "cloudflare", name: "Cloudflare", address: "1.1.1.1")
    static let google = DNSResolver(id: "google", name: "Google", address: "8.8.8.8")

    static let builtIn: [DNSResolver] = [.system, .cloudflare, .google]

    static func custom(_ address: String) -> DNSResolver? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return DNSResolver(id: "custom:\(trimmed)", name: trimmed, address: trimmed)
    }
}

// MARK: - Certificates

struct TLSCertificate: Identifiable, Equatable, Sendable {
    let id: UUID
    let subject: String
    let issuer: String
    let notBefore: Date?
    let notAfter: Date?

    init(
        id: UUID = UUID(),
        subject: String,
        issuer: String,
        notBefore: Date?,
        notAfter: Date?
    ) {
        self.id = id
        self.subject = subject
        self.issuer = issuer
        self.notBefore = notBefore
        self.notAfter = notAfter
    }
}

struct TLSCertificateReport: Equatable, Sendable {
    let host: String
    let port: UInt16
    let certificates: [TLSCertificate]
    let trusted: Bool
    let checkedAt: Date

    var leaf: TLSCertificate? { certificates.first }

    var daysRemaining: Int? {
        guard let notAfter = leaf?.notAfter else { return nil }
        return Calendar(identifier: .gregorian).dateComponents(
            [.day], from: Date(), to: notAfter
        ).day
    }

    var expired: Bool { (daysRemaining ?? 1) < 0 }
    var expiresSoon: Bool { (daysRemaining ?? .max) <= 30 }
}

// MARK: - Traceroute

struct TracerouteHop: Identifiable, Equatable, Sendable {
    let ttl: Int
    let address: String?
    let hostname: String?
    let milliseconds: [Double]
    let timedOut: Bool

    var id: Int { ttl }

    var averageMilliseconds: Double? {
        guard !milliseconds.isEmpty else { return nil }
        return milliseconds.reduce(0, +) / Double(milliseconds.count)
    }

    init(
        ttl: Int,
        address: String?,
        hostname: String? = nil,
        milliseconds: [Double] = [],
        timedOut: Bool = false
    ) {
        self.ttl = ttl
        self.address = address
        self.hostname = hostname
        self.milliseconds = milliseconds
        self.timedOut = timedOut
    }
}

struct TracerouteReport: Equatable, Sendable {
    let host: String
    let hops: [TracerouteHop]
    let startedAt: Date

    var reachedTarget: Bool { hops.last?.address != nil }
}

// MARK: - Ports

enum PortState: String, CaseIterable, Sendable {
    case open
    case closed
    case filtered

    var label: String {
        switch self {
        case .open: return String(localized: "Open")
        case .closed: return String(localized: "Closed")
        case .filtered: return String(localized: "Filtered")
        }
    }
}

struct PortScanResult: Identifiable, Equatable, Sendable {
    let port: UInt16
    let service: String?
    let state: PortState
    let responseMilliseconds: Double?
    let detail: String?

    var id: UInt16 { port }

    init(
        port: UInt16,
        service: String? = nil,
        state: PortState,
        responseMilliseconds: Double? = nil,
        detail: String? = nil
    ) {
        self.port = port
        self.service = service
        self.state = state
        self.responseMilliseconds = responseMilliseconds
        self.detail = detail
    }
}

// MARK: - Internet check verdict

enum DiagnosticVerdict: String, Equatable, Sendable {
    case healthy
    case localNetwork
    case router
    case provider
    case dns
    case web

    var title: String {
        switch self {
        case .healthy: return String(localized: "Everything looks fine")
        case .localNetwork: return String(localized: "Most likely your Wi-Fi")
        case .router: return String(localized: "Most likely your router")
        case .provider: return String(localized: "Most likely your provider")
        case .dns: return String(localized: "Most likely DNS")
        case .web: return String(localized: "Most likely the website")
        }
    }

    var detail: String {
        switch self {
        case .healthy:
            return String(localized: "This Mac, the Wi-Fi, the router, DNS and the web all answer normally.")
        case .localNetwork:
            return String(
                localized: "The Wi-Fi link is weak or has no address. Move closer to the router, or reconnect.")
        case .router:
            return String(
                localized: "The Wi-Fi link is fine, but the router does not answer. Reboot it and check the cable.")
        case .provider:
            return
                "The router answers, but packets are lost or delayed past it. This is usually the line or the provider."
        case .dns:
            return String(localized: "The connection works, but name resolution fails. Check the DNS servers.")
        case .web:
            return String(
                localized:
                    "DNS and the router are fine, but the web check fails. The site or an upstream service is down.")
        }
    }

    var isProblem: Bool { self != .healthy }
}
