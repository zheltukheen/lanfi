import Foundation

struct Iperf3Measurement: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let host: String
    let port: UInt16
    let direction: Iperf3Direction
    let headlineMegabitsPerSecond: Double?
    let testedAt: Date

    init(
        id: UUID = UUID(),
        host: String,
        port: UInt16,
        direction: Iperf3Direction,
        headlineMegabitsPerSecond: Double?,
        testedAt: Date
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.direction = direction
        self.headlineMegabitsPerSecond = headlineMegabitsPerSecond
        self.testedAt = testedAt
    }

    init(report: Iperf3Report) {
        self.init(
            host: report.host,
            port: report.port,
            direction: report.direction,
            headlineMegabitsPerSecond: report.headlineMegabitsPerSecond,
            testedAt: report.testedAt
        )
    }
}

struct Iperf3Server: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let host: String
    let port: UInt16

    init(id: UUID = UUID(), name: String, host: String, port: UInt16) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }
}

struct Iperf3HistoryStore: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support =
                FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first ?? FileManager.default.temporaryDirectory
            self.fileURL =
                support
                .appendingPathComponent("LanFi", isDirectory: true)
                .appendingPathComponent("iperf3-history.json")
        }
    }

    func load() throws -> [Iperf3Measurement] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Iperf3Measurement].self, from: data)
    }

    func save(_ measurements: [Iperf3Measurement]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(measurements).write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
