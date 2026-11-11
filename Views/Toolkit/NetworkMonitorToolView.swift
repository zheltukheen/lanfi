import AppKit
import SwiftUI

struct NetworkMonitorToolView: View {
    @ObservedObject var interfaces: InterfacesViewModel
    @State private var tab: NetworkMonitorTab =
        ProcessInfo.processInfo.arguments.contains("--routes") ? .routes : .overview
    @State private var routes: [NetworkRoute] = []
    @State private var isLoadingRoutes = false
    @State private var routesError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Mode", selection: $tab) {
                    ForEach(NetworkMonitorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
                Spacer()
                if tab == .routes {
                    Button {
                        Task { await loadRoutes() }
                    } label: {
                        if isLoadingRoutes {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingRoutes)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            switch tab {
            case .overview:
                InterfacesView(interfaces: interfaces)
            case .routes:
                routesContent
            }
        }
        .task(id: tab) {
            if interfaces.report.interfaces.isEmpty {
                await interfaces.refresh()
            }
            if tab == .routes, routes.isEmpty { await loadRoutes() }
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
            .padding(14)
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

    private var routesTable: some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Routing table")
                    Spacer()
                    Text("IPv4 · netstat -rn -f inet")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(routes) {
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
                    .width(90)
                    TableColumn("Interface") { route in
                        Text(route.interface)
                            .font(.caption.monospaced())
                    }
                    .width(90)
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
