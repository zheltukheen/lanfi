import Foundation

enum ProtocolFactStatus: String, Codable {
    case good
    case info
    case warning
    case critical
    case unknown
}

struct ProtocolFact: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let detail: String?
    let status: ProtocolFactStatus

    init(
        id: String,
        label: String,
        value: String,
        detail: String? = nil,
        status: ProtocolFactStatus = .info
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.detail = detail
        self.status = status
    }
}

struct ProtocolBlock: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let facts: [ProtocolFact]
    let status: ProtocolFactStatus
}

struct ProtocolProfile: Equatable {
    let networkId: String
    let title: String
    let subtitle: String
    let formatLine: String
    let band: WiFiBand
    let blocks: [ProtocolBlock]
    let warnings: [String]
}

struct ProtocolCoverage: Equatable {
    let networkCount: Int
    let bandCounts: [String: Int]
    let generationCounts: [String: Int]
    let securityCounts: [String: Int]
    let sixGHzCount: Int
    let wiFi7Count: Int
    let pmfCount: Int
    let wpsCount: Int
    let fastTransitionCount: Int
    let openCount: Int
    let criticalCount: Int

    static let empty = ProtocolCoverage(
        networkCount: 0,
        bandCounts: [:],
        generationCounts: [:],
        securityCounts: [:],
        sixGHzCount: 0,
        wiFi7Count: 0,
        pmfCount: 0,
        wpsCount: 0,
        fastTransitionCount: 0,
        openCount: 0,
        criticalCount: 0
    )

    var securitySummary: String {
        securityCounts.max { $0.value < $1.value }?.key ?? "—"
    }

    var generationSummary: String {
        generationCounts.max { $0.value < $1.value }?.key ?? "—"
    }
}
