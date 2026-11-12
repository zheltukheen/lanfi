import Foundation

/// Writes the latest scan into the MCP drop folder so an agent running the
/// `lanfi-cli mcp` server can analyse live results without touching CoreWLAN.
enum MCPSnapshotWriter {
    static func write(_ payload: [String: Any]) {
        let url = MCPPaths.liveSnapshotURL
        guard JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys])
        else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // The snapshot is a convenience for external agents; never surface
            // its failure in the UI.
        }
    }
}
