import Foundation

/// File locations shared by the app and the CLI MCP server.
enum MCPPaths {
    /// Latest live scan written by the running app. Agents read this, so they
    /// do not need Location access or a second CoreWLAN scan of their own.
    static var liveSnapshotURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return
            support
            .appendingPathComponent("LanFi", isDirectory: true)
            .appendingPathComponent("mcp", isDirectory: true)
            .appendingPathComponent("latest-scan.json")
    }
}
