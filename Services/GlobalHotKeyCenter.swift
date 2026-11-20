import AppKit
import Carbon.HIToolbox
import Foundation

/// Registers the optional global shortcut that opens Connections.
///
/// Carbon's `RegisterEventHotKey` is used deliberately: it needs no
/// Accessibility permission and it tells us when another app already owns the
/// combination, which is the conflict rule this feature needs. A failed
/// registration restores whatever was registered before, so recording a taken
/// shortcut never leaves the user without a working one.
@MainActor
final class GlobalHotKeyCenter: ObservableObject {
    static let shared = GlobalHotKeyCenter()

    @Published private(set) var hotKey: GlobalHotKey?
    @Published private(set) var lastError: String?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        hotKey = GlobalHotKeyStore.load()
        if let hotKey {
            do {
                try register(hotKey)
            } catch {
                lastError = error.localizedDescription
                self.hotKey = nil
                GlobalHotKeyStore.save(nil)
            }
        }
    }

    /// Records a new shortcut, or clears it with nil.
    func set(_ newValue: GlobalHotKey?) {
        let previous = hotKey
        unregister()
        guard let newValue else {
            hotKey = nil
            lastError = nil
            GlobalHotKeyStore.save(nil)
            return
        }
        do {
            try register(newValue)
            hotKey = newValue
            lastError = nil
            GlobalHotKeyStore.save(newValue)
        } catch {
            // Put the old one back so the shortcut the user had still works.
            if let previous, (try? register(previous)) != nil {
                hotKey = previous
            } else {
                hotKey = nil
                GlobalHotKeyStore.save(nil)
            }
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
    }

    // MARK: - Carbon

    private func register(_ hotKey: GlobalHotKey) throws {
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: OSType(0x4C61_6E46), id: 1)  // 'LanF'
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.carbonModifiers, identifier, GetApplicationEventTarget(), 0,
            &reference)
        switch status {
        case noErr:
            self.reference = reference
        case OSStatus(eventHotKeyExistsErr):
            throw GlobalHotKeyError.taken
        default:
            throw GlobalHotKeyError.failed("The shortcut could not be registered (\(status)).")
        }
    }

    private func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in center.fire() }
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Opens the Connections tool in the main window. The notification is the
    /// same one the menu bar and Diagnostics use, so the shortcut cannot drift
    /// from those entry points.
    private func fire() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(
            name: .lanfiShowToolkit, object: nil,
            userInfo: ["tool": ToolboxTool.openConnections.rawValue])
    }
}
