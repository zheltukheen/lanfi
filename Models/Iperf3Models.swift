import Foundation

enum Iperf3Direction: String, CaseIterable, Identifiable, Sendable, Codable {
    case upload
    case download
    case bidirectional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: return String(localized: "Upload")
        case .download: return String(localized: "Download")
        case .bidirectional: return String(localized: "Bidirectional")
        }
    }

    var argument: String? {
        switch self {
        case .upload: return nil
        case .download: return "-R"
        case .bidirectional: return "--bidir"
        }
    }
}

struct Iperf3Interval: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Double
    let end: Double
    let megabitsPerSecond: Double

    init(
        id: UUID = UUID(),
        start: Double,
        end: Double,
        megabitsPerSecond: Double
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.megabitsPerSecond = megabitsPerSecond
    }
}

struct Iperf3Report: Equatable, Sendable {
    let host: String
    let port: UInt16
    let direction: Iperf3Direction
    let sentMegabitsPerSecond: Double?
    let receivedMegabitsPerSecond: Double?
    let summaryMegabitsPerSecond: Double?
    let intervals: [Iperf3Interval]
    let durationSeconds: Double?
    let testedAt: Date

    var headlineMegabitsPerSecond: Double? {
        switch direction {
        case .upload: return sentMegabitsPerSecond ?? summaryMegabitsPerSecond
        case .download: return receivedMegabitsPerSecond ?? summaryMegabitsPerSecond
        case .bidirectional: return summaryMegabitsPerSecond ?? sentMegabitsPerSecond
        }
    }
}

enum Iperf3Parser {
    static func parse(
        _ data: Data,
        host: String,
        port: UInt16,
        direction: Iperf3Direction
    ) throws -> Iperf3Report {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            throw Iperf3Error.invalidOutput
        }
        let intervals = (object["intervals"] as? [[String: Any]] ?? []).compactMap {
            interval -> Iperf3Interval? in
            guard let sum = interval["sum"] as? [String: Any],
                let bits = number(sum["bits_per_second"])
            else { return nil }
            return Iperf3Interval(
                start: number(sum["start"]) ?? 0,
                end: number(sum["end"]) ?? 0,
                megabitsPerSecond: bits / 1_000_000
            )
        }
        let end = object["end"] as? [String: Any]
        let sent = (end?["sum_sent"] as? [String: Any]).flatMap {
            number($0["bits_per_second"])
        }.map { $0 / 1_000_000 }
        let received = (end?["sum_received"] as? [String: Any]).flatMap {
            number($0["bits_per_second"])
        }.map { $0 / 1_000_000 }
        let summary = (end?["sum"] as? [String: Any]).flatMap {
            number($0["bits_per_second"])
        }.map { $0 / 1_000_000 }

        return Iperf3Report(
            host: host,
            port: port,
            direction: direction,
            sentMegabitsPerSecond: sent,
            receivedMegabitsPerSecond: received,
            summaryMegabitsPerSecond: summary,
            intervals: intervals,
            durationSeconds: intervals.last?.end,
            testedAt: Date()
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }
}

enum Iperf3Error: Error, Equatable, LocalizedError {
    case notInstalled
    case invalidOutput
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "iperf3 is not installed. Install it with: brew install iperf3"
        case .invalidOutput:
            return "iperf3 returned data that could not be parsed."
        case .failed(let message):
            return message.isEmpty ? "iperf3 failed." : message
        }
    }
}

struct Iperf3Runner {
    static let candidates = [
        "/opt/homebrew/bin/iperf3",
        "/usr/local/bin/iperf3",
        "/usr/bin/iperf3",
    ]

    static func locate() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func arguments(
        host: String,
        port: UInt16,
        durationSeconds: Int,
        direction: Iperf3Direction
    ) -> [String] {
        var arguments = [
            "-c", host,
            "-p", String(port),
            "-t", String(max(1, min(durationSeconds, 120))),
            "-J",
        ]
        if let extra = direction.argument { arguments.append(extra) }
        return arguments
    }

    func run(
        host: String,
        port: UInt16,
        durationSeconds: Int,
        direction: Iperf3Direction
    ) async throws -> Iperf3Report {
        try await Task.detached(priority: .utility) {
            guard let executable = Self.locate() else { throw Iperf3Error.notInstalled }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Self.arguments(
                host: host, port: port, durationSeconds: durationSeconds, direction: direction)
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
            } catch {
                throw Iperf3Error.failed(error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(Double(durationSeconds) + 15)
            while process.isRunning && Date() < deadline {
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                } catch {
                    process.terminate()
                    throw error
                }
            }
            if process.isRunning {
                process.terminate()
                throw Iperf3Error.failed("iperf3 did not finish in time.")
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw Iperf3Error.failed(
                    errorText.isEmpty ? "iperf3 exited with \(process.terminationStatus)." : errorText)
            }
            return try Iperf3Parser.parse(
                data, host: host, port: port, direction: direction)
        }.value
    }
}
