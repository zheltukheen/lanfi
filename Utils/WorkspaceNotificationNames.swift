import Foundation

/// The in-app navigation channel. These names live in `Utils` because both the
/// app and `Services` post them (the global shortcut opens Connections from
/// `Services`), and because the shared test target compiles `Services` without
/// the `Views` folder.
extension Notification.Name {
    static let lanfiFocusSearch = Notification.Name("LanFi.focusSearch")
    static let lanfiShowWiFiTool = Notification.Name("LanFi.showWiFiTool")
    static let lanfiSelectBottomTab = Notification.Name("LanFi.selectBottomTab")
    static let lanfiShowInspector = Notification.Name("LanFi.showInspector")
    static let lanfiShowToolkit = Notification.Name("LanFi.showToolkit")
    static let lanfiSelectShelfDevice = Notification.Name("LanFi.selectShelfDevice")
    static let lanfiShowCommandPalette = Notification.Name("LanFi.showCommandPalette")
}
