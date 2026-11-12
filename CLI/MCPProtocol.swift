import Foundation

/// Transport-free MCP JSON-RPC handling. `MCPServer` only moves lines over
/// stdio; everything testable lives here.
enum MCPProtocol {
    static let version = "2024-11-05"
    static let serverName = "lanfi"
    static let serverVersion = "1.0.0"

    /// Returns the response object, or nil for a notification.
    static func handle(_ request: [String: Any]) async -> [String: Any]? {
        let id = request["id"]
        guard let method = request["method"] as? String else {
            return errorResponse(id, code: -32600, message: "Missing method.")
        }
        switch method {
        case "initialize":
            return result(
                id,
                [
                    "protocolVersion": version,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": serverName, "version": serverVersion],
                    "instructions":
                        "LanFi exposes Wi-Fi scan analysis and network probes. Scan tools read the live snapshot written by the running app unless `path` points at an exported scan JSON.",
                ])
        case "notifications/initialized", "initialized":
            return nil
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": MCPToolkit.definitions])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                let name = params["name"] as? String
            else {
                return errorResponse(id, code: -32602, message: "Invalid tools/call params.")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let outcome = await MCPToolkit.call(name, arguments: arguments) else {
                return errorResponse(id, code: -32602, message: "Unknown tool: \(name)")
            }
            return result(
                id,
                [
                    "content": [["type": "text", "text": outcome.text]],
                    "isError": outcome.isError,
                ])
        default:
            return errorResponse(id, code: -32601, message: "Unknown method: \(method)")
        }
    }

    private static func result(_ id: Any?, _ value: [String: Any]) -> [String: Any]? {
        guard let id else { return nil }
        return ["jsonrpc": "2.0", "id": id, "result": value]
    }

    private static func errorResponse(
        _ id: Any?,
        code: Int,
        message: String
    ) -> [String: Any]? {
        guard let id else { return nil }
        return ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }
}
