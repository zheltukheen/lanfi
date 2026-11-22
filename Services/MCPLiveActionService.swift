import AppKit
import CoreWLAN
import Foundation
import LanFiCore

/// Executes live MCP actions inside the running app.
///
/// The CLI cannot scan Wi-Fi, open a capture or touch the survey itself: those
/// live in the GUI process. This service watches the mailbox
/// (`MCPLiveActionStore`) and runs the registered handler on the main actor.
/// It only runs when the user has enabled live actions in Settings → MCP.
@MainActor
final class MCPLiveActionService: ObservableObject {
    static let shared = MCPLiveActionService()

    typealias Handler =
        @MainActor (MCPLiveActionRequest) async -> MCPLiveActionResponse

    private var handlers: [MCPLiveAction: Handler] = [:]
    private var timer: Timer?
    private var inFlight: Set<UUID> = []
    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL = MCPLiveActionStore.defaultDirectory, defaults: UserDefaults = .standard) {
        self.directory = directory
        self.defaults = defaults
    }

    var isEnabled: Bool {
        defaults.bool(forKey: AppSettingsKey.mcpLiveActions.rawValue)
    }

    func register(_ action: MCPLiveAction, handler: @escaping Handler) {
        handlers[action] = handler
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One pass over the inbox. Exposed for tests and for `--ui-smoke`.
    func poll() {
        guard isEnabled, handlers.isEmpty == false else { return }
        MCPLiveActionStore.prune(directory: directory)
        for request in MCPLiveActionStore.pending(directory: directory) {
            guard !inFlight.contains(request.id) else { continue }
            guard let handler = handlers[request.action] else {
                MCPLiveActionStore.take(request, directory: directory)
                let response = MCPLiveActionResponse(
                    id: request.id, action: request.action, ok: false,
                    message: "This build has no handler for \(request.action.title).")
                try? MCPLiveActionStore.respond(response, directory: directory)
                continue
            }
            MCPLiveActionStore.take(request, directory: directory)
            inFlight.insert(request.id)
            Task { @MainActor [weak self] in
                let response = await handler(request)
                try? MCPLiveActionStore.respond(response, directory: directory)
                self?.inFlight.remove(request.id)
            }
        }
    }
}
