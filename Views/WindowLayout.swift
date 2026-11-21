import AppKit
import SwiftUI

/// Keeps the main window inside the screen.
///
/// macOS restores the last window frame, so a window that was once laid out on
/// a larger display (or dragged taller than the screen) comes back with its
/// bottom — and the bottom of the survey plan — off the display, where nothing
/// can be clicked. Resizing only happens when the frame does not fit: a user
/// who chose a smaller window keeps it.
enum WindowLayout {
    @MainActor
    static func fitMainWindowToScreen() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }),
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let visible = screen.visibleFrame
        let frame = window.frame
        let fits =
            frame.height <= visible.height + 1 && frame.width <= visible.width + 1
            && visible.minY - 1 <= frame.minY && frame.maxY <= visible.maxY + 1
        guard !fits else { return }
        var fitted = frame
        fitted.size.width = min(frame.width, visible.width)
        fitted.size.height = min(frame.height, visible.height)
        fitted.origin.x = min(max(frame.minX, visible.minX), visible.maxX - fitted.width)
        fitted.origin.y = min(max(frame.minY, visible.minY), visible.maxY - fitted.height)
        window.setFrame(fitted, display: true)
    }
}

/// Reports the window as soon as SwiftUI gives the view one.
///
/// An `onAppear` call was too early: at that point the window did not exist yet,
/// so the correction silently did nothing and the off-screen window stayed.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = FitterView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FitterView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async {
                WindowLayout.fitMainWindowToScreen()
            }
            // SwiftUI applies its own frame one turn later; a second pass costs
            // nothing when the first one already fitted the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                WindowLayout.fitMainWindowToScreen()
            }
        }
    }
}
