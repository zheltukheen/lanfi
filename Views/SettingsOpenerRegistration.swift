import SwiftUI

/// Hands SwiftUI's own "open Settings" action to `SettingsRouter`.
///
/// `@Environment(\.openSettings)` exists on macOS 14, which is why this lives in
/// its own availability-gated view instead of a selector string.
@available(macOS 14.0, *)
struct SettingsOpenerRegistration: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsRouter.shared.registerOpenHandler {
                    openSettings()
                }
            }
    }
}
