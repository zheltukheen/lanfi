import SwiftUI

/// One tab strip for the whole app. Screens that need tabs pass sections and
/// get the same type scale, spacing, selection colour and accessibility traits
/// instead of rebuilding a segmented picker each time.
struct AppTabBar: View {
    struct Item: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let icon: String
    }

    struct Section: Identifiable {
        let id: String
        let title: LocalizedStringKey?
        let items: [Item]
    }

    let sections: [Section]
    @Binding var selection: String
    var showsGroupTitles = true

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Divider()
                        .frame(height: 30)
                        .padding(.horizontal, DesignToken.Spacing.small)
                        .padding(.bottom, 2)
                }
                VStack(spacing: 1) {
                    if showsGroupTitles, let title = section.title {
                        Text(title)
                            .font(.system(size: 8, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(.secondary.opacity(0.75))
                    }
                    HStack(spacing: 0) {
                        ForEach(section.items) { item in
                            tab(item)
                        }
                    }
                }
                .padding(.horizontal, DesignToken.Spacing.tight)
            }
        }
    }

    private func tab(_ item: Item) -> some View {
        let isSelected = selection == item.id
        return Button {
            selection = item.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                Text(item.title)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .padding(.horizontal, DesignToken.Spacing.medium)
            .padding(.vertical, DesignToken.Spacing.tight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(item.title)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
