import Foundation

struct MTRHop: Identifiable, Equatable, Sendable {
    let hop: Int
    let address: String?
    let hostname: String?
    let sent: Int
    let received: Int
    let lastMilliseconds: Double?
    let bestMilliseconds: Double?
    let worstMilliseconds: Double?
    let averageMilliseconds: Double?
    let jitterMilliseconds: Double?

    var id: Int { hop }

    var lossPercent: Double {
        guard sent > 0 else { return 0 }
        return Double(sent - received) / Double(sent) * 100
    }
}

struct MTRReport: Equatable, Sendable {
    let host: String
    let rounds: Int
    let startedAt: Date
    let hops: [MTRHop]

    var reachedTarget: Bool { hops.last?.address != nil }
}
