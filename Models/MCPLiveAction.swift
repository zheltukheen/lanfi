import Foundation

/// Live MCP actions ask the running app to do something, instead of reading a
/// snapshot. They travel through a small file mailbox under Application
/// Support: the CLI writes a request, the app watches the inbox, executes it on
/// its view models and writes a response. No socket is opened and nothing
/// leaves the Mac.
enum MCPLiveAction: String, Codable, CaseIterable, Sendable {
    case scanNow = "scan_now"
    case startCapture = "start_capture"
    case surveySample = "survey_sample"

    var title: String {
        switch self {
        case .scanNow: return "Scan now"
        case .startCapture: return "Start capture"
        case .surveySample: return "Survey sample"
        }
    }
}

struct MCPLiveActionRequest: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let action: MCPLiveAction
    var arguments: [String: String]
    let createdAt: Date

    init(
        id: UUID = UUID(), action: MCPLiveAction, arguments: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.action = action
        self.arguments = arguments
        self.createdAt = createdAt
    }
}

struct MCPLiveActionResponse: Codable, Equatable, Sendable {
    let id: UUID
    let action: MCPLiveAction
    let ok: Bool
    let message: String
    var payload: [String: String]

    init(
        id: UUID, action: MCPLiveAction, ok: Bool, message: String,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.action = action
        self.ok = ok
        self.message = message
        self.payload = payload
    }
}

/// The on-disk protocol. Every method takes the directory so tests can point it
/// at a temporary folder; the app and CLI use `defaultDirectory`.
enum MCPLiveActionStore {
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return
            support
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("mcp", isDirectory: true)
            .appendingPathComponent("live", isDirectory: true)
    }

    private static var inbox: (URL) -> URL {
        { $0.appendingPathComponent("inbox", isDirectory: true) }
    }

    private static var outbox: (URL) -> URL {
        { $0.appendingPathComponent("outbox", isDirectory: true) }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func prepare(_ directory: URL) throws {
        for folder in [inbox(directory), outbox(directory)] {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        }
    }

    /// Writes one request and returns its id.
    @discardableResult
    static func submit(
        _ request: MCPLiveActionRequest, directory: URL = defaultDirectory
    ) throws -> UUID {
        try prepare(directory)
        let data = try encoder().encode(request)
        try data.write(
            to: inbox(directory).appendingPathComponent("\(request.id.uuidString).json"),
            options: .atomic)
        return request.id
    }

    /// Requests waiting for the app, oldest first. Undecodable files are
    /// ignored so one bad writer cannot stall the queue.
    static func pending(directory: URL = defaultDirectory) -> [MCPLiveActionRequest] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: inbox(directory), includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = decoder()
        return
            files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(MCPLiveActionRequest.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Removes a request once the app has taken it. A crash loses that one
    /// request; the caller sees a timeout and can retry.
    static func take(_ request: MCPLiveActionRequest, directory: URL = defaultDirectory) {
        try? FileManager.default.removeItem(
            at: inbox(directory).appendingPathComponent("\(request.id.uuidString).json"))
    }

    static func respond(
        _ response: MCPLiveActionResponse, directory: URL = defaultDirectory
    ) throws {
        try prepare(directory)
        let data = try encoder().encode(response)
        try data.write(
            to: outbox(directory).appendingPathComponent("\(response.id.uuidString).json"),
            options: .atomic)
    }

    static func response(
        id: UUID, directory: URL = defaultDirectory
    ) -> MCPLiveActionResponse? {
        let url = outbox(directory).appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(MCPLiveActionResponse.self, from: data)
    }

    /// Blocks the calling thread until the response appears or the deadline
    /// passes. CLI handlers run this off the main thread.
    static func waitForResponse(
        id: UUID, directory: URL = defaultDirectory, timeout: TimeInterval
    ) -> MCPLiveActionResponse? {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline {
            if let response = response(id: id, directory: directory) {
                return response
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return response(id: id, directory: directory)
    }

    /// Removes responses and abandoned requests older than `age`, so the folder
    /// does not grow forever.
    static func prune(directory: URL = defaultDirectory, olderThan age: TimeInterval = 600) {
        let cutoff = Date().addingTimeInterval(-max(60, age))
        for folder in [inbox(directory), outbox(directory)] {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            else { continue }
            for file in files {
                let modified =
                    (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let modified, modified < cutoff {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }
}
