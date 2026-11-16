import AppKit
import SwiftUI

struct BottomPanelTabs: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer()

            TabGroup("OVERVIEW") {
                TabButton(
                    title: "Overview",
                    icon: "sparkles",
                    isSelected: selectedTab == 0,
                    action: { selectedTab = 0 }
                )
            }

            groupDivider

            TabGroup("NETWORK") {
                TabButton(
                    title: "Profile",
                    icon: "square.stack.3d.up",
                    isSelected: selectedTab == 1,
                    action: { selectedTab = 1 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Raw Data",
                    icon: "list.bullet.rectangle",
                    isSelected: selectedTab == 3,
                    action: { selectedTab = 3 }
                )
            }

            groupDivider

            TabGroup("RF") {
                TabButton(
                    title: "All Bands",
                    icon: "rectangle.split.3x1",
                    isSelected: selectedTab == 9,
                    action: { selectedTab = 9 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Spectrum",
                    icon: "waveform.path.ecg",
                    isSelected: selectedTab == 4,
                    action: { selectedTab = 4 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "History",
                    icon: "clock.arrow.circlepath",
                    isSelected: selectedTab == 5,
                    action: { selectedTab = 5 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Monitor",
                    icon: "waveform.path.ecg.rectangle",
                    isSelected: selectedTab == 8,
                    action: { selectedTab = 8 }
                )
                Divider().frame(height: 18)
                TabButton(
                    title: "Capture",
                    icon: "record.circle",
                    isSelected: selectedTab == 7,
                    action: { selectedTab = 7 }
                )
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Material.bar)
    }

    private var groupDivider: some View {
        Divider()
            .frame(height: 30)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }
}

struct TabGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(.secondary.opacity(0.75))
            HStack(spacing: 0) { content }
        }
        .padding(.horizontal, 5)
    }
}
