import Foundation

public struct MTRHop: Identifiable, Equatable, Sendable {
    public let hop: Int
    public let address: String?
    public let hostname: String?
    public let sent: Int
    public let received: Int
    public let lastMilliseconds: Double?
    public let bestMilliseconds: Double?
    public let worstMilliseconds: Double?
    public let averageMilliseconds: Double?
    public let jitterMilliseconds: Double?

    public init(
        hop: Int,
        address: String?,
        hostname: String?,
        sent: Int,
        received: Int,
        lastMilliseconds: Double?,
        bestMilliseconds: Double?,
        worstMilliseconds: Double?,
        averageMilliseconds: Double?,
        jitterMilliseconds: Double?
    ) {
        self.hop = hop
        self.address = address
        self.hostname = hostname
        self.sent = sent
        self.received = received
        self.lastMilliseconds = lastMilliseconds
        self.bestMilliseconds = bestMilliseconds
        self.worstMilliseconds = worstMilliseconds
        self.averageMilliseconds = averageMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
    }

    public var id: Int { hop }

    public var lossPercent: Double {
        guard sent > 0 else { return 0 }
        return Double(sent - received) / Double(sent) * 100
    }
}

public struct MTRReport: Equatable, Sendable {
    public let host: String
    public let rounds: Int
    public let startedAt: Date
    public let hops: [MTRHop]

    public init(host: String, rounds: Int, startedAt: Date, hops: [MTRHop]) {
        self.host = host
        self.rounds = rounds
        self.startedAt = startedAt
        self.hops = hops
    }

    public var reachedTarget: Bool { hops.last?.address != nil }
}
