import SwiftUI

/// One screen for Whois and GeoIP: one target field, two answers.
///
/// Both tools take the same input (a domain, host or address) and are usually
/// consulted together — "who owns this name and where does it live" — so they
/// share one tab strip instead of two sidebar rows. The query is mirrored
/// between the models, so switching tabs keeps the target.
struct WhoisGeoIPToolView: View {
    @ObservedObject var whois: WhoisToolModel
    @ObservedObject var geo: GeoIPToolModel
    @ObservedObject var toolkit: ToolkitViewModel

    private enum Tab: String, CaseIterable, Identifiable {
        case whois
        case geo

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .whois: return "Whois"
            case .geo: return "GeoIP"
            }
        }
        var icon: String {
            switch self {
            case .whois: return "doc.text.magnifyingglass"
            case .geo: return "mappin.and.ellipse"
            }
        }
    }

    @State private var tab: Tab = .whois

    var body: some View {
        VStack(spacing: 0) {
            ToolkitHeaderBar {
                AppTabBar(
                    sections: [
                        .init(
                            id: "whoisGeoIP", title: nil,
                            items: Tab.allCases.map {
                                .init(id: $0.rawValue, title: $0.title, icon: $0.icon)
                            })
                    ],
                    selection: Binding(
                        get: { tab.rawValue },
                        set: { tab = Tab(rawValue: $0) ?? tab }),
                    showsGroupTitles: false)
            } trailing: {
                Text(targetLine)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            switch tab {
            case .whois:
                WhoisToolView(model: whois)
            case .geo:
                GeoIPToolView(model: geo)
            }
        }
        .onAppear { syncTab(with: toolkit.selection) }
        .onChange(of: toolkit.selection) { selection in syncTab(with: selection) }
        .onChange(of: whois.query) { value in
            if !value.isEmpty { geo.query = value }
        }
        .onChange(of: geo.query) { value in
            if !value.isEmpty { whois.query = value }
        }
    }

    /// A deep link to either tool opens its own tab; the sidebar row opens the
    /// last tab the user chose.
    private func syncTab(with tool: ToolboxTool) {
        switch tool {
        case .geoIP: tab = .geo
        case .whois: tab = .whois
        default: break
        }
    }

    private var targetLine: String {
        switch tab {
        case .whois: return whois.query.isEmpty ? String(localized: "No target yet") : whois.query
        case .geo: return geo.query.isEmpty ? String(localized: "No target yet") : geo.query
        }
    }
}
