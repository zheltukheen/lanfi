import AppKit
import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError, Equatable {
    case needsModifier
    case reserved(String)
    case taken
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .needsModifier:
            return "Use at least one of ⌘, ⌃ or ⌥ with the key."
        case .reserved(let display):
            return "\(display) is reserved by macOS or a menu item here."
        case .taken:
            return "Another app already uses that shortcut."
        case .failed(let message):
            return message
        }
    }
}

/// One recorded global shortcut. Carbon's constants are the currency because
/// `RegisterEventHotKey` is what actually registers it; the display string is
/// built here so the UI and the log never disagree about what was recorded.
struct GlobalHotKey: Equatable, Codable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    static let option = UInt32(optionKey)
    static let control = UInt32(controlKey)
    static let shift = UInt32(shiftKey)
    static let command = UInt32(cmdKey)

    static func modifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.control) { value |= control }
        if flags.contains(.option) { value |= option }
        if flags.contains(.shift) { value |= shift }
        if flags.contains(.command) { value |= command }
        return value
    }

    /// Builds a shortcut from a real key press. Returns the reason instead of a
    /// silent nil, so the recorder can say what is wrong with what was pressed.
    static func record(from event: NSEvent) -> Result<GlobalHotKey, GlobalHotKeyError> {
        let carbon = modifiers(from: event.modifierFlags)
        let key = keyName(for: event)
        guard !key.isEmpty else {
            return .failure(.failed("That key cannot be used."))
        }
        switch validate(carbonModifiers: carbon, key: key) {
        case .failure(let error):
            return .failure(error)
        case .success:
            let display = displayString(carbonModifiers: carbon, key: key)
            return .success(
                GlobalHotKey(
                    keyCode: UInt32(event.keyCode), carbonModifiers: carbon, display: display))
        }
    }

    /// The conflict rule: the shortcut needs a real modifier (Shift alone types
    /// a capital letter), and the combinations macOS or our own menu already own
    /// are refused by name instead of failing silently at registration.
    static func validate(
        carbonModifiers: UInt32, key: String
    ) -> Result<Void, GlobalHotKeyError> {
        guard carbonModifiers & (command | control | option) != 0 else {
            return .failure(.needsModifier)
        }
        let normalized = key.uppercased()
        let display = displayString(carbonModifiers: carbonModifiers, key: normalized)
        if reserved(display) { return .failure(.reserved(display)) }
        return .success(())
    }

    /// Combinations the system or LanFi's own menus keep for themselves.
    static func reserved(_ display: String) -> Bool {
        let reserved: Set<String> = [
            "⌘Q", "⌘W", "⌘H", "⌘M", "⌘TAB", "⌘SPACE", "⌃⌘Q", "⌘⇧3", "⌘⇧4", "⌘⇧5", "⌘,", "⌘K",
        ]
        return reserved.contains(display)
    }

    static func displayString(carbonModifiers: UInt32, key: String) -> String {
        var text = ""
        if carbonModifiers & control != 0 { text += "⌃" }
        if carbonModifiers & option != 0 { text += "⌥" }
        if carbonModifiers & shift != 0 { text += "⇧" }
        if carbonModifiers & command != 0 { text += "⌘" }
        return text + key
    }

    /// A printable name for the pressed key: letters and digits as typed,
    /// everything else by code so a space or an arrow reads sensibly.
    static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case 49: return "SPACE"
        case 36: return "RETURN"
        case 48: return "TAB"
        case 53: return "ESC"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 51: return "⌫"
        default: break
        }
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return ""
        }
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.uppercased()
    }

    var carbonFlagsDescription: String { display }
}

/// Persists the one shortcut. Only one owner, and no default: until the user
/// records something, LanFi registers nothing.
enum GlobalHotKeyStore {
    static let key = "LanFi.globalHotKey"

    static func load(from defaults: UserDefaults = .standard) -> GlobalHotKey? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GlobalHotKey.self, from: data)
    }

    static func save(_ hotKey: GlobalHotKey?, to defaults: UserDefaults = .standard) {
        guard let hotKey else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(hotKey) {
            defaults.set(data, forKey: key)
        }
    }
}
