import AppKit
import SwiftUI

extension Notification.Name {
    static let lanfiFocusSearch = Notification.Name("LanFi.focusSearch")
    static let lanfiShowWiFiTool = Notification.Name("LanFi.showWiFiTool")
    static let lanfiSelectBottomTab = Notification.Name("LanFi.selectBottomTab")
    static let lanfiShowInspector = Notification.Name("LanFi.showInspector")
    static let lanfiShowToolkit = Notification.Name("LanFi.showToolkit")
    static let lanfiSelectShelfDevice = Notification.Name("LanFi.selectShelfDevice")
}

// MARK: - Subviews

struct ErrorBanner: View {
    let message: String
    let onClose: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
            Text(message).font(.callout).foregroundColor(.primary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss message")
        }
        .padding(DesignToken.Spacing.small)
        .background(Color.yellow.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.yellow.opacity(0.3)), alignment: .bottom)
    }
}
