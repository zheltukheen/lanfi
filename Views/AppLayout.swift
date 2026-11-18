import SwiftUI

/// Shared sheet chrome. Every sheet gets the same padding, alignment and
/// minimum width instead of its own numbers, and large sheets opt into the
/// wide token rather than inventing a width.
private struct AppSheetModifier: ViewModifier {
    let width: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(DesignToken.Layout.sheetPadding)
            .frame(minWidth: width, minHeight: minHeight, alignment: .topLeading)
    }
}

extension View {
    func appSheet(
        width: CGFloat = DesignToken.Layout.sheetWidth,
        minHeight: CGFloat = DesignToken.Layout.sheetMinHeight
    ) -> some View {
        modifier(AppSheetModifier(width: width, minHeight: minHeight))
    }

    /// The standard content inset for tool screens and scroll views.
    func appContentPadding() -> some View {
        padding(DesignToken.Layout.contentPadding)
    }
}

/// A sheet title block: icon, title, one-line explanation and trailing actions.
struct AppSheetHeader<Trailing: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
                Text(title).font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignToken.Spacing.medium)
            trailing
        }
    }
}

extension AppSheetHeader where Trailing == EmptyView {
    init(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Column widths for the app's SwiftUI tables, matched to the AppKit column
/// catalog's scale so every table reads at the same density.
enum AppColumnWidth {
    static let index: CGFloat = 40
    static let tiny: CGFloat = 50
    static let small: CGFloat = 55
    static let short: CGFloat = 65
    static let compact: CGFloat = 90
    static let medium: CGFloat = 120
    static let wide: CGFloat = 150
    static let long: CGFloat = 180
    static let flexibleMin: CGFloat = 160
}

extension View {
    /// Consistent table surface: rounded card, hairline border and the shared
    /// row density. Height is supplied by the caller because tables differ.
    func appTableSurface(cornerRadius: CGFloat = DesignToken.Radius.card) -> some View {
        background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: DesignToken.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
