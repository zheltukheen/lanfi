import Foundation

/// A Model Context Protocol server over stdio so AI agents can read the scan
/// LanFi collected and run the same probes the toolkit screens run.
///
/// Run it with `lanfi-cli mcp` and register that command in the MCP client.
/// The server never scans Wi-Fi itself: it reads the live snapshot the app
/// writes while it is open, or any exported scan JSON you point it at.
/// The protocol and tools live in `MCPProtocol` and `MCPToolkit` so they can be
/// tested without a client.
enum MCPServer {
    static func run() -> Never {
        let group = DispatchGroup()
        group.enter()
        Task.detached {
            await serve()
            group.leave()
        }
        group.wait()
        exit(0)
    }

    private static func serve() async {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                let data = trimmed.data(using: .utf8),
                let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let response = await MCPProtocol.handle(request) {
                send(response)
            }
        }
    }

    private static func send(_ object: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.withoutEscapingSlashes]),
            let text = String(data: data, encoding: .utf8)
        else { return }
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }
}
