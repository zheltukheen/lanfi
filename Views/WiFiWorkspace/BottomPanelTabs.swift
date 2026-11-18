import AppKit
import SwiftUI

/// Bottom tab strip of the Wi-Fi workspace, built on the shared `AppTabBar`
/// so the whole app uses one tab treatment.
struct BottomPanelTabs: View {
    @Binding var selectedTab: Int

    private var selection: Binding<String> {
        Binding(
            get: { String(selectedTab) },
            set: { selectedTab = Int($0) ?? selectedTab }
        )
    }

    var body: some View {
        HStack {
            Spacer()
            AppTabBar(
                sections: [
                    AppTabBar.Section(
                        id: "overview",
                        title: "OVERVIEW",
                        items: [
                            .init(id: "0", title: "Overview", icon: "sparkles")
                        ]
                    ),
                    AppTabBar.Section(
                        id: "network",
                        title: "NETWORK",
                        items: [
                            .init(id: "1", title: "Profile", icon: "square.stack.3d.up"),
                            .init(id: "3", title: "Raw Data", icon: "list.bullet.rectangle"),
                        ]
                    ),
                    AppTabBar.Section(
                        id: "rf",
                        title: "RF",
                        items: [
                            .init(id: "9", title: "All Bands", icon: "rectangle.split.3x1"),
                            .init(id: "4", title: "Spectrum", icon: "waveform.path.ecg"),
                            .init(id: "5", title: "History", icon: "clock.arrow.circlepath"),
                            .init(id: "8", title: "Monitor", icon: "waveform.path.ecg.rectangle"),
                            .init(id: "7", title: "Capture", icon: "record.circle"),
                        ]
                    ),
                ],
                selection: selection
            )
            Spacer()
        }
        .padding(.horizontal, DesignToken.Spacing.small)
        .padding(.vertical, DesignToken.Spacing.tight)
        .background(Material.bar)
    }
}
