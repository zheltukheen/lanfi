import AppKit
import SwiftUI

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
        .background(DesignToken.Surface.warningFill)
        .overlay(
            Rectangle().frame(height: 1)
                .foregroundColor(DesignToken.Surface.tintStroke(AppPalette.warning)),
            alignment: .bottom)
    }
}
