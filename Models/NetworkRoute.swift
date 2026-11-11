import Foundation

struct NetworkRoute: Identifiable, Equatable, Sendable {
    let destination: String
    let gateway: String
    let flags: String
    let interface: String
    let expire: String?

    var id: String { "\(destination)-\(gateway)-\(interface)" }
    var isDefault: Bool { destination == "default" }
}

enum RouteTableParser {
    static func parse(_ text: String) -> [NetworkRoute] {
        var routes: [NetworkRoute] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("Destination")
                || trimmed.hasPrefix("Routing tables")
                || trimmed.hasPrefix("Internet")
                || trimmed.hasPrefix("Netif")
            {
                continue
            }
            let columns = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 4 else { continue }
            guard columns[0] != "Destination" else { continue }
            routes.append(
                NetworkRoute(
                    destination: columns[0],
                    gateway: columns[1],
                    flags: columns[2],
                    interface: columns[3],
                    expire: columns.count > 4 ? columns[4] : nil
                ))
        }
        return routes.sorted {
            if $0.isDefault != $1.isDefault { return $0.isDefault }
            return $0.destination.localizedStandardCompare($1.destination) == .orderedAscending
        }
    }
}

enum RouteTableError: Error, LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The system netstat binary is unavailable."
        case .failed(let message): return message.isEmpty ? "Could not read the route table." : message
        }
    }
}

struct RouteTableReader {
    func read() async throws -> [NetworkRoute] {
        try await Task.detached(priority: .utility) {
            let executable = "/usr/sbin/netstat"
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw RouteTableError.unavailable
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["-rn", "-f", "inet"]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(
                decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw RouteTableError.failed(errorText)
            }
            return RouteTableParser.parse(String(decoding: data, as: UTF8.self))
        }.value
    }
}
