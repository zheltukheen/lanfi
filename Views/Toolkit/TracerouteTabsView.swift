import SwiftUI

/// One Traceroute screen with a second tab for continuous MTR.
///
/// The classic trace, the map and the sortable hop table were already one view;
/// MTR is the same question asked repeatedly (per-hop loss and jitter over
/// time), so it sits behind the same target field instead of a second sidebar
/// entry. A deep link to `mtr` still lands here, on the Continuous tab.
struct TracerouteTabsView: View {
    @ObservedObject var visual: VisualTracerouteToolModel
    @ObservedObject var mtr: MTRToolModel
    @ObservedObject var toolkit: ToolkitViewModel

    enum Tab: String, CaseIterable, Identifiable {
        case trace
        case continuous

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .trace: return "Route"
            case .continuous: return "Continuous"
            }
        }
        var icon: String {
            switch self {
            case .trace: return "point.3.connected.trianglepath.dotted"
            case .continuous: return "chart.line.uptrend.xyaxis"
            }
        }
    }

    @State private var tab: Tab = .trace

    var body: some View {
        VStack(spacing: 0) {
            ToolkitHeaderBar {
                AppTabBar(
                    sections: [
                        .init(
                            id: "traceroute", title: nil,
                            items: Tab.allCases.map {
                                .init(id: $0.rawValue, title: $0.title, icon: $0.icon)
                            })
                    ],
                    selection: Binding(
                        get: { tab.rawValue },
                        set: { tab = Tab(rawValue: $0) ?? tab }),
                    showsGroupTitles: false)
            } trailing: {
                Text(tab == .trace ? visual.host : mtr.host)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            switch tab {
            case .trace:
                VisualTracerouteToolView(model: visual)
            case .continuous:
                MTRToolView(model: mtr)
            }
        }
        .onAppear { syncTab(with: toolkit.selection) }
        .onChange(of: toolkit.selection) { selection in syncTab(with: selection) }
        .onChange(of: visual.host) { value in
            if !value.isEmpty, mtr.host.isEmpty { mtr.host = value }
        }
    }

    private func syncTab(with tool: ToolboxTool) {
        if tool == .mtr { tab = .continuous }
    }
}
