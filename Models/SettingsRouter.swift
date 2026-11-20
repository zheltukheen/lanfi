import AppKit

/// The single path from anywhere in the app to one Settings page.
///
/// The Settings scene has no public "select this page" API, so the selection
/// travels through this router: whoever asks for a page stores it here and the
/// Settings view applies it when it appears (or when the value changes), no
/// matter how the window itself was opened.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    /// The page the next Settings appearance should show.
    @Published private(set) var pending: SettingsSection?

    private var openHandler: (@MainActor () -> Void)?

    /// macOS 14+ registers SwiftUI's own settings action here, so opening the
    /// window does not depend on a private string selector.
    func registerOpenHandler(_ handler: @escaping @MainActor () -> Void) {
        openHandler = handler
    }

    /// Records the page without touching any window. This is what tests drive.
    func request(_ section: SettingsSection) {
        pending = section
    }

    /// Returns the requested page once and clears it, so a later appearance of
    /// the Settings window does not re-select an old page.
    func takePending() -> SettingsSection? {
        defer { pending = nil }
        return pending
    }

    /// Requests a page and brings the Settings window forward.
    func open(_ section: SettingsSection) {
        request(section)
        NSApp.activate(ignoringOtherApps: true)
        if let openHandler {
            openHandler()
            return
        }
        Self.openLegacySettingsWindow()
    }

    /// macOS 13 fallback: the Settings scene still answers to the window action
    /// the application menu uses. Only reached when the SwiftUI action is not
    /// available.
    private static func openLegacySettingsWindow() {
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
