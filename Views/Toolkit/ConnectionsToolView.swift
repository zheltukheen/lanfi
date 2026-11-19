import SwiftUI

/// One screen for "what is using this Mac's network": the read-only TCP socket
/// list, the opt-in per-process rates and the local block rules. They answer the
/// same question from three sides — which process, on which endpoint, moving how
/// much — so they share one sidebar entry and a tab strip instead of separate
/// near-identical tools.
struct ConnectionsToolView: View {
    @ObservedObject var toolkit: ToolkitViewModel
    @StateObject private var rules = ConnectionRulesModel()
    @State private var tab = "sockets"

    private var selection: Binding<String> {
        Binding(
            get: { tab },
            set: { id in
                tab = id
                if id == "traffic" {
                    toolkit.select(.processTraffic)
                } else if id == "sockets" {
                    toolkit.select(.openConnections)
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolkitHeaderBar {
                AppTabBar(
                    sections: [
                        .init(
                            id: "connections",
                            title: nil,
                            items: [
                                .init(id: "sockets", title: "Sockets", icon: "arrow.triangle.branch"),
                                .init(
                                    id: "traffic", title: "Traffic",
                                    icon: "arrow.up.arrow.down.circle"),
                                .init(id: "rules", title: "Rules", icon: "shield.lefthalf.filled"),
                            ])
                    ],
                    selection: selection,
                    showsGroupTitles: false
                )
            }

            Group {
                switch tab {
                case "traffic":
                    ProcessTrafficToolView(rules: rules)
                case "rules":
                    ConnectionRulesView(rules: rules)
                default:
                    OpenConnectionsToolView(rules: rules)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if toolkit.selection == .processTraffic { tab = "traffic" }
        }
        .onChange(of: toolkit.selection) { selection in
            if selection == .processTraffic { tab = "traffic" }
            if selection == .openConnections, tab == "traffic" { tab = "sockets" }
        }
    }
}
