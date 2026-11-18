import Foundation
import ServiceManagement

/// Launch-at-login via the modern `SMAppService` API (macOS 13+). No helper
/// bundle, no privileged install. A failed registration (for example an app
/// run from a translocated or unsigned location) is surfaced instead of hidden.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var errorMessage: String?

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return String(localized: "LanFi starts when you log in.")
        case .requiresApproval:
            return String(localized: "Waiting for approval in System Settings → General → Login Items.")
        case .notRegistered: return String(localized: "LanFi does not start at login.")
        case .notFound: return String(localized: "The login item is unavailable for this build.")
        @unknown default: return String(localized: "Unknown login-item state.")
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
