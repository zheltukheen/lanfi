import AppKit
import SwiftUI

struct NetworkMonitorToolView: View {
    @ObservedObject var interfaces: InterfacesViewModel
    @StateObject private var accounting = TrafficAccounting.shared
    @State private var tab: NetworkMonitorTab =
        ProcessInfo.processInfo.arguments.contains("--routes") ? .routes : .overview
    @State private var routes: [NetworkRoute] = []
    @State private var routesLoaded = false
    @State private var isLoadingRoutes = false
    @State private var routesError: String?

    var body: some View {
        VStack(spacing: 0) {
            ToolkitHeaderBar {
                AppTabBar(
                    sections: [
                        .init(
                            id: "monitor", title: nil,
                            items: [
                                .init(
                                    id: NetworkMonitorTab.overview.rawValue,
                                    title: "Overview", icon: "gauge"),
                                .init(
                                    id: NetworkMonitorTab.routes.rawValue,
                                    title: "Routes", icon: "arrow.triangle.branch"),
                            ])
                    ],
                    selection: tabSelection,
                    showsGroupTitles: false)
            } trailing: {
                if tab == .routes {
                    AppButton(
                        "Refresh", systemImage: "arrow.clockwise", isBusy: isLoadingRoutes
                    ) {
                        Task { await loadRoutes() }
                    }
                }
            }

            switch tab {
            case .overview:
                VStack(spacing: 0) {
                    usageCard
                        .padding(.horizontal, DesignToken.Spacing.card)
                        .padding(.top, DesignToken.Spacing.medium)
                    InterfacesView(interfaces: interfaces)
                }
            case .routes:
                routesContent
            }
        }
        .task(id: tab) {
            if interfaces.report.interfaces.isEmpty {
                await interfaces.refresh()
            }
            if tab == .routes, !routesLoaded { await loadRoutes() }
        }
    }

    private var routesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let routesError {
                    ToolkitErrorBanner(message: routesError)
                }
                if !routes.isEmpty {
                    summary
                    routesTable
                } else if !isLoadingRoutes {
                    ToolkitEmptyState(
                        icon: "arrow.triangle.branch",
                        title: "No routes found",
                        message: "The system route table is empty or could not be read."
                    )
                }
            }
            .padding(DesignToken.Spacing.card)
        }
    }

    private var tabSelection: Binding<String> {
        Binding(
            get: { tab.rawValue },
            set: { raw in tab = NetworkMonitorTab(rawValue: raw) ?? .overview })
    }

    /// P2: day/week/month/total volumes from the interface counters, stored
    /// locally next to the other LanFi stores.
    private var usageCard: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack(spacing: DesignToken.Spacing.small) {
                    ToolkitSectionLabel(text: "Data usage")
                    Spacer()
                    Button("Export CSV…") { accounting.exportCSV() }
                        .controlSize(.small)
                    Button("Reset") { accounting.reset() }
                        .controlSize(.small)
                }
                HStack(spacing: 24) {
                    ForEach(TrafficRange.allCases) { range in
                        ToolkitMetric(
                            title: LocalizedStringKey(range.title),
                            value: TrafficByteFormat.string(accounting.volume(range).total))
                    }
                    Spacer()
                }
                Text(
                    "Counted from the interface byte counters once a minute; the ledger stays on this Mac."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private var summary: some View {
        ToolkitCard {
            HStack(spacing: 20) {
                ToolkitMetric(title: "Routes", value: "\(routes.count)")
                ToolkitMetric(
                    title: "Default route",
                    value: defaultRoute?.gateway ?? "—")
                ToolkitMetric(
                    title: "Primary interface",
                    value: interfaces.report.primaryInterface ?? "—")
                Spacer()
            }
        }
    }

    private var defaultRoute: NetworkRoute? {
        let defaults = routes.filter(\.isDefault)
        if let primary = interfaces.report.primaryInterface,
            let matching = defaults.first(where: { $0.interface == primary })
        {
            return matching
        }
        return defaults.first
    }

    private enum RouteSortKey: String, CaseIterable, Identifiable {
        case destination, gateway, flags, interface, expire
        var id: String { rawValue }
        var title: String {
            switch self {
            case .destination: return String(localized: "Destination")
            case .gateway: return String(localized: "Gateway")
            case .flags: return String(localized: "Flags")
            case .interface: return String(localized: "Interface")
            case .expire: return String(localized: "Expire")
            }
        }
    }

    @State private var routeSortKey: RouteSortKey = .destination
    @State private var routeAscending = true

    private func sortedRoutes(_ rows: [NetworkRoute]) -> [NetworkRoute] {
        let ordered = rows.sorted { lhs, rhs in
            switch routeSortKey {
            case .destination:
                return lhs.destination.compare(rhs.destination, options: .numeric)
                    == .orderedAscending
            case .gateway:
                return lhs.gateway.localizedStandardCompare(rhs.gateway) == .orderedAscending
            case .flags: return lhs.flags.localizedStandardCompare(rhs.flags) == .orderedAscending
            case .interface:
                return lhs.interface.localizedStandardCompare(rhs.interface) == .orderedAscending
            case .expire:
                return (lhs.expire ?? "").localizedStandardCompare(rhs.expire ?? "")
                    == .orderedAscending
            }
        }
        return routeAscending ? ordered : ordered.reversed()
    }

    private var routesTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Routing table")
                    if !routes.isEmpty {
                        TableSortControl(
                            options: RouteSortKey.allCases.map { ($0, $0.title) },
                            selection: $routeSortKey, ascending: $routeAscending)
                    }
                    Spacer()
                    Text("IPv4 · netstat -rn -f inet")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DesignToken.Spacing.card)
                .padding(.top, DesignToken.Spacing.medium)
                .padding(.bottom, DesignToken.Spacing.tight)

                Table(sortedRoutes(routes)) {
                    TableColumn("Destination") { route in
                        HStack(spacing: 5) {
                            if route.isDefault {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            Text(route.destination)
                                .font(.caption.monospaced())
                        }
                    }
                    TableColumn("Gateway") { route in
                        Text(route.gateway)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    TableColumn("Flags") { route in
                        Text(route.flags)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                    .width(AppColumnWidth.compact)
                    TableColumn("Interface") { route in
                        Text(route.interface)
                            .font(.caption.monospaced())
                    }
                    .width(AppColumnWidth.compact)
                    TableColumn("Expire") { route in
                        Text(route.expire ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(70)
                }
                .frame(height: min(CGFloat(routes.count) * 24 + 44, 540))
            }
        }
    }

    private func loadRoutes() async {
        guard !isLoadingRoutes else { return }
        isLoadingRoutes = true
        routesError = nil
        do {
            routes = try await RouteTableReader().read()
            routesLoaded = true
        } catch {
            routesError = error.localizedDescription
        }
        isLoadingRoutes = false
    }
}

private enum NetworkMonitorTab: String, CaseIterable, Identifiable {
    case overview, routes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .routes: return String(localized: "Routes")
        }
    }
}
