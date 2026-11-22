import Foundation

extension MCPToolkit {
    /// Sends one live action to the running app and waits for its response.
    /// The wait runs off the main thread: `startCapture` can sit behind the
    /// administrator authorization prompt for as long as the capture lasts.
    static func liveAction(
        _ action: MCPLiveAction, arguments: [String: Any]
    ) async -> MCPToolOutcome {
        var values: [String: String] = [:]
        for (key, value) in arguments {
            if let value = value as? String {
                values[key] = value
            } else if let value = value as? Bool {
                values[key] = value ? "true" : "false"
            } else if let value = value as? Int {
                values[key] = String(value)
            } else if let value = value as? Double {
                values[key] = String(value)
            }
        }
        let duration = max(5, min(Int(values["duration"] ?? "") ?? 10, 120))
        let timeout = action == .startCapture ? Double(duration) + 120 : 25
        let request = MCPLiveActionRequest(action: action, arguments: values)

        let outcome: MCPToolOutcome = await Task.detached(priority: .userInitiated) {
            do {
                let id = try MCPLiveActionStore.submit(request)
                guard
                    let response = MCPLiveActionStore.waitForResponse(
                        id: id, timeout: timeout)
                else {
                    return .error(
                        """
                        LanFi did not answer the live action within \(Int(timeout)) s.
                        Keep the app running and enable Settings → MCP → “Allow MCP clients to act on the running app”.
                        """)
                }
                guard response.ok else { return .error(response.message) }
                var object = response.payload
                object["ok"] = "true"
                object["message"] = response.message
                return .json(object)
            } catch {
                return .error(
                    "Could not write the live-action request: \(error.localizedDescription)")
            }
        }.value
        return outcome
    }
}
