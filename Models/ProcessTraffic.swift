import Foundation

/// One per-process row from `nettop -P -x -l 1 -J bytes_in,bytes_out`.
struct ProcessTrafficRow: Identifiable, Equatable {
    let process: String
    let pid: Int
    let bytesIn: UInt64
    let bytesOut: UInt64

    var id: String { "\(process)|\(pid)" }
    var totalBytes: UInt64 { bytesIn + bytesOut }
}

/// Bytes transferred between two nettop samples, with per-second rates.
struct ProcessTrafficDelta: Identifiable, Equatable {
    let process: String
    let pid: Int
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let receivedBytesPerSecond: Double
    let sentBytesPerSecond: Double

    var id: String { "\(process)|\(pid)" }
    var totalBytes: UInt64 { receivedBytes + sentBytes }
    var totalBytesPerSecond: Double { receivedBytesPerSecond + sentBytesPerSecond }
}

enum ProcessTrafficParser {
    /// Parses the `-J bytes_in,bytes_out` layout. Process names can contain
    /// spaces, so the two counters are read from the end of the line.
    static func parse(_ output: String) -> [ProcessTrafficRow] {
        var rows: [ProcessTrafficRow] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("bytes_in") else { continue }
            let parts = trimmed.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3,
                let bytesIn = UInt64(parts[parts.count - 2]),
                let bytesOut = UInt64(parts[parts.count - 1])
            else { continue }

            let nameAndPID = parts.dropLast(2).joined(separator: " ")
            guard let dot = nameAndPID.lastIndex(of: "."),
                let pid = Int(nameAndPID[nameAndPID.index(after: dot)...])
            else { continue }
            let process = String(nameAndPID[..<dot])
            guard !process.isEmpty else { continue }
            rows.append(
                ProcessTrafficRow(
                    process: process, pid: pid, bytesIn: bytesIn, bytesOut: bytesOut))
        }
        return rows.sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.process.localizedStandardCompare(rhs.process) == .orderedAscending
        }
    }

    /// Joins two cumulative snapshots. Counters can reset when a process
    /// restarts, so negative deltas are clamped to zero.
    static func deltas(
        previous: [ProcessTrafficRow],
        current: [ProcessTrafficRow],
        interval: TimeInterval
    ) -> [ProcessTrafficDelta] {
        let seconds = max(0.1, interval)
        let before = Dictionary(
            previous.map { ("\($0.process)|\($0.pid)", $0) },
            uniquingKeysWith: { first, _ in first })
        let result = current.map { row -> ProcessTrafficDelta in
            let old = before[row.id]
            let received = row.bytesIn >= (old?.bytesIn ?? 0) ? row.bytesIn - (old?.bytesIn ?? 0) : 0
            let sent = row.bytesOut >= (old?.bytesOut ?? 0) ? row.bytesOut - (old?.bytesOut ?? 0) : 0
            return ProcessTrafficDelta(
                process: row.process,
                pid: row.pid,
                receivedBytes: received,
                sentBytes: sent,
                receivedBytesPerSecond: Double(received) / seconds,
                sentBytesPerSecond: Double(sent) / seconds)
        }
        return result.sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.process.localizedStandardCompare(rhs.process) == .orderedAscending
        }
    }
}

enum ProcessTrafficService {
    static let toolPath = "/usr/bin/nettop"

    /// Two overlapping snapshots one second apart. Each `nettop -l 1` call
    /// reports a five-second window, so running them concurrently keeps the
    /// pair to roughly six seconds instead of ten.
    static func sample(interval: TimeInterval = 1) async throws -> [ProcessTrafficDelta] {
        let firstTask = Task { try await snapshot() }
        try await Task.sleep(nanoseconds: UInt64(max(0.2, interval) * 1_000_000_000))
        let secondTask = Task { try await snapshot() }
        let first = try await firstTask.value
        let second = try await secondTask.value
        return ProcessTrafficParser.deltas(
            previous: first, current: second, interval: interval)
    }

    static func snapshot() async throws -> [ProcessTrafficRow] {
        try await Task.detached(priority: .userInitiated) {
            try readSnapshot()
        }.value
    }

    private static func readSnapshot() throws -> [ProcessTrafficRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["-P", "-x", "-l", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "LanFi.ProcessTraffic", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "nettop exited with an error."])
        }
        return ProcessTrafficParser.parse(String(decoding: data, as: UTF8.self))
    }
}

enum ProcessTrafficFormat {
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 B/s" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = bytesPerSecond
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[unit])
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }
}
