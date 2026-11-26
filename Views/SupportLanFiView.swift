import LanFiCore
import SwiftUI

/// Support sheet opened from the heart at the bottom of the sidebar. The list
/// is the same `.github/FUNDING.yml` that GitHub renders, copied into the app
/// bundle at build time — adding a link there and rebuilding is all it takes.
struct SupportLanFiView: View {
    @Environment(\.dismiss) private var dismiss
    private let options = FundingService.options()

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            header
            if options.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DesignToken.Spacing.small) {
                        ForEach(options) { option in
                            FundingOptionButton(option: option)
                        }
                    }
                    .padding(.vertical, DesignToken.Spacing.hairline)
                }
            }
            footer
        }
        .appSheet(width: DesignToken.Layout.sheetWidth, minHeight: 360)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignToken.Spacing.medium) {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundColor(.pink)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignToken.Spacing.hairline) {
                Text("Support LanFi")
                    .font(.title3.bold())
                Text(
                    "LanFi is a spare-time project. These are the places where you can support its development — the same links GitHub shows on the repository's Sponsor button."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Close") { dismiss() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
            Text("No support links are available in this build.")
                .font(.callout)
            Text("Add one under `custom:` in `.github/FUNDING.yml` and rebuild.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: DesignToken.Spacing.small) {
            Image(systemName: "doc.text")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Read from .github/FUNDING.yml at build time. Nothing is downloaded.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// One support destination, rendered as a full-width button that opens in the
/// browser. A Link keeps the standard hover and selection behaviour.
private struct FundingOptionButton: View {
    let option: FundingOption

    var body: some View {
        Link(destination: option.url) {
            HStack(spacing: DesignToken.Spacing.medium) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundColor(.pink)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: option.title)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(verbatim: option.detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(DesignToken.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .appCardSurface()
        }
        .buttonStyle(.plain)
        .help("Open \(option.url.absoluteString)")
        .accessibilityLabel("Support via \(option.title)")
    }
}
