import Foundation

enum DiagnosticStatus: Int, Codable, Comparable {
    case pending = 0
    case running = 1
    case pass = 2
    case warning = 3
    case fail = 4
    case skipped = 5

    static func < (lhs: DiagnosticStatus, rhs: DiagnosticStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .pass: return "Pass"
        case .warning: return "Warning"
        case .fail: return "Fail"
        case .skipped: return "Skipped"
        }
    }
}

enum DiagnosticCategory: String, Codable, CaseIterable, Identifiable {
    case link
    case network
    case dns
    case internet
    case performance
    case security

    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: return "Wi-Fi link"
        case .network: return "Local network"
        case .dns: return "DNS"
        case .internet: return "Internet"
        case .performance: return "Performance"
        case .security: return "Security"
        }
    }

    var systemImage: String {
        switch self {
        case .link: return "wifi"
        case .network: return "network"
        case .dns: return "server.rack"
        case .internet: return "globe"
        case .performance: return "speedometer"
        case .security: return "lock.shield"
        }
    }
}

struct DiagnosticCheck: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let category: DiagnosticCategory
    let status: DiagnosticStatus
    let value: String
    let detail: String
    let durationMilliseconds: Int?
    var recommendation: String? = nil
}

struct DiagnosticsReport: Identifiable, Equatable, Codable {
    let id: String
    let startedAt: Date
    let finishedAt: Date
    let snapshot: LinkSnapshot
    let checks: [DiagnosticCheck]

    var overall: DiagnosticStatus {
        if checks.contains(where: { $0.status == .fail }) { return .fail }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        if checks.contains(where: { $0.status == .pass }) { return .pass }
        return .pending
    }

    var failedCount: Int { checks.filter { $0.status == .fail }.count }
    var warningCount: Int { checks.filter { $0.status == .warning }.count }
    var passedCount: Int { checks.filter { $0.status == .pass }.count }
    var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    var healthScore: Int {
        let scored = checks.filter { $0.status != .skipped && $0.status != .pending }
        guard !scored.isEmpty else { return 0 }
        let points = scored.reduce(0) { total, check in
            switch check.status {
            case .pass: return total + 100
            case .warning: return total + 55
            case .fail: return total
            default: return total + 50
            }
        }
        return points / scored.count
    }

    var summary: String {
        if checks.isEmpty { return "No diagnostics run" }
        if failedCount > 0 { return "\(failedCount) failed, \(warningCount) warning" }
        if warningCount > 0 { return "\(warningCount) warning, \(passedCount) passed" }
        return "All \(passedCount) checks passed"
    }
}

struct LinkSnapshot: Equatable, Codable {
    let interfaceName: String?
    let ssid: String?
    let bssid: String?
    let powerOn: Bool
    let serviceActive: Bool
    let rssi: Int?
    let noise: Int?
    let snr: Int?
    let transmitRateMbps: Double?
    let channel: Int?
    let band: String?
    let widthMHz: Int?
    let security: String?
    let ipv4Addresses: [String]
    let ipv6Addresses: [String]
    let router: String?
    let dnsServers: [String]

    static let empty = LinkSnapshot(
        interfaceName: nil,
        ssid: nil,
        bssid: nil,
        powerOn: false,
        serviceActive: false,
        rssi: nil,
        noise: nil,
        snr: nil,
        transmitRateMbps: nil,
        channel: nil,
        band: nil,
        widthMHz: nil,
        security: nil,
        ipv4Addresses: [],
        ipv6Addresses: [],
        router: nil,
        dnsServers: []
    )

    var isConnected: Bool {
        powerOn && serviceActive && (ssid != nil || bssid != nil)
    }

    var primaryIPv4: String? { ipv4Addresses.first }
}

// MARK: - Transport results

struct PingResult: Equatable {
    let transmitted: Int
    let received: Int
    let packetLossPercent: Double
    let minMilliseconds: Double?
    let averageMilliseconds: Double?
    let maxMilliseconds: Double?
    let standardDeviationMilliseconds: Double?
}

struct DNSResult: Equatable {
    let host: String
    let addresses: [String]
    let milliseconds: Int
}

struct HTTPResult: Equatable {
    let statusCode: Int
    let finalURL: URL?
    let bodyPrefix: String
    let milliseconds: Int
}

enum PingOutputParser {
    static func parse(_ output: String) -> PingResult? {
        let lines = output.components(separatedBy: .newlines)
        guard
            let summary = lines.first(where: { $0.contains("packets transmitted") || $0.contains("packet transmitted") }
            )
        else {
            return nil
        }

        let numbers = summary.split(whereSeparator: { !$0.isNumber && $0 != "." }).compactMap { Double($0) }
        // macOS: "3 packets transmitted, 3 packets received, 0.0% packet loss"
        guard numbers.count >= 3 else { return nil }
        let transmitted = Int(numbers[0])
        let received = Int(numbers[1])
        let loss = numbers[2]

        var minMs: Double?
        var avgMs: Double?
        var maxMs: Double?
        var stddevMs: Double?
        if let roundTrip = lines.first(where: { $0.contains("round-trip") || $0.contains("rtt") }) {
            let values =
                roundTrip
                .split(separator: "=", maxSplits: 1)
                .last?
                .split(separator: "/")
                .compactMap {
                    Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ms", with: ""))
                } ?? []
            if values.count >= 4 {
                minMs = values[0]
                avgMs = values[1]
                maxMs = values[2]
                stddevMs = values[3]
            }
        }

        return PingResult(
            transmitted: transmitted,
            received: received,
            packetLossPercent: loss,
            minMilliseconds: minMs,
            averageMilliseconds: avgMs,
            maxMilliseconds: maxMs,
            standardDeviationMilliseconds: stddevMs
        )
    }
}
