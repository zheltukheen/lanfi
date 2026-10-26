import Foundation

struct ThroughputReport: Equatable {
    let downloadMbps: Double?
    let uploadMbps: Double?
    let latencyMilliseconds: Double?
    let responsiveness: Double?
    let testedAt: Date

    var summary: String {
        let down = downloadMbps.map { String(format: "%.0f Mbps down", $0) } ?? "down —"
        let up = uploadMbps.map { String(format: "%.0f Mbps up", $0) } ?? "up —"
        let latency = latencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "latency —"
        return "\(down) · \(up) · \(latency)"
    }
}

enum ThroughputTester {
    static func run(timeout: Int = 20) async throws -> ThroughputReport {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c", "-s", "-M", String(max(5, min(timeout, 60)))]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let errorText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "LanFi.Throughput", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorText.isEmpty
                        ? "networkQuality failed." : errorText
                ])
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "LanFi.Throughput", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "networkQuality returned no JSON."
                ])
        }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> ThroughputReport {
        func number(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = object[key] as? Double { return value }
                if let value = object[key] as? Int { return Double(value) }
                if let value = object[key] as? NSNumber { return value.doubleValue }
            }
            return nil
        }
        return ThroughputReport(
            downloadMbps: number(["dl_throughput", "download_throughput"]).map { $0 / 1_000_000 },
            uploadMbps: number(["ul_throughput", "upload_throughput"]).map { $0 / 1_000_000 },
            latencyMilliseconds: number(["idle_latency", "latency"]),
            responsiveness: number(["responsiveness"]),
            testedAt: Date()
        )
    }
}
