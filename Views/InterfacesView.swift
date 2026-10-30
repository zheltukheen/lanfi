import SwiftUI

struct InterfacesView: View {
    @ObservedObject var interfaces: InterfacesViewModel
    @State private var showInactive = true

    private var activeInterfaces: [SystemInterface] {
        interfaces.report.interfaces.filter { item in
            item.isUp && (item.isPrimary || !item.ipv4.isEmpty || !item.ipv6.isEmpty || item.kind == .wifi)
        }
    }

    private var inactiveInterfaces: [SystemInterface] {
        interfaces.report.interfaces.filter { !activeInterfaces.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if interfaces.report.interfaces.isEmpty {
                    emptyState
                } else {
                    summary
                    ForEach(grouped(activeInterfaces), id: \.0) { category, items in
                        interfaceSection(category, items: items)
                    }

                    if !inactiveInterfaces.isEmpty {
                        DisclosureGroup(isExpanded: $showInactive) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(grouped(inactiveInterfaces), id: \.0) { category, items in
                                    interfaceSection(category, items: items)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Image(systemName: "eye.slash")
                                Text("Inactive interfaces (\(inactiveInterfaces.count))")
                                    .font(.caption.bold())
                                Spacer()
                            }
                            .foregroundColor(.primary)
                        }
                        .padding(10)
                    }
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .task {
            if interfaces.report.interfaces.isEmpty {
                await interfaces.refresh()
            }
            while !Task.isCancelled {
                if interfaces.autoRefresh {
                    await interfaces.refresh()
                }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func interfaceSection(_ category: String, items: [SystemInterface]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(category)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 310), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(items) { interface in
                    InterfaceCard(interface: interface)
                }
            }
        }
    }

    private func grouped(_ items: [SystemInterface]) -> [(String, [SystemInterface])] {
        let groups = Dictionary(grouping: items) { $0.kind.category }
        return groups.keys.sorted { lhs, rhs in
            let left = groups[lhs]?.map(\.kind.sortOrder).min() ?? 99
            let right = groups[rhs]?.map(\.kind.sortOrder).min() ?? 99
            return left < right
        }.map { ($0, groups[$0]?.sorted { $0.kind.sortOrder < $1.kind.sortOrder } ?? []) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Network interfaces")
                    .font(.headline)
                Text("Every BSD interface on this Mac — physical, virtual, VPN, bridge and loopback.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(interfaces.lastUpdatedText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Auto-refresh", isOn: $interfaces.autoRefresh)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button {
                Task { await interfaces.refresh() }
            } label: {
                if interfaces.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(interfaces.isScanning)
            Button {
                interfaces.copyReport()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copy interface report")
        }
    }

    private var summary: some View {
        HStack(spacing: 9) {
            summaryCard("Interfaces", "\(interfaces.report.interfaces.count)", tint: .accentColor)
            summaryCard("Interfaces Up", "\(interfaces.report.upCount)", tint: .green)
            summaryCard("Primary", interfaces.report.primaryInterface ?? "—", tint: .blue)
            summaryCard("Tunnels / VPN", "\(interfaces.report.tunnelCount)", tint: .purple)
            summaryCard("Router", interfaces.report.router ?? "—", tint: .orange)
            summaryCard("DNS", interfaces.report.dnsServers.first ?? "—", tint: .teal)
        }
    }

    private func summaryCard(_ title: LocalizedStringKey, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "network.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.35))
            Text("No interfaces found")
                .font(.headline)
            Text("LanFi could not enumerate BSD network interfaces.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Scan Again") { Task { await interfaces.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

private struct InterfaceCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let interface: SystemInterface

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: interface.kind.systemImage)
                    .foregroundColor(interface.isUp ? .accentColor : .secondary)
                    .frame(width: 18)
                Text(interface.displayName)
                    .font(.caption.bold())
                    .lineLimit(1)
                Spacer()
                if interface.isPrimary {
                    Text("PRIMARY")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(interface.statusLabel)
                    .font(.caption2.bold())
                    .foregroundColor(interface.isUp ? .green : .secondary)
            }

            Divider()

            fact("Type", interface.kind.title)
            fact("MAC", interface.macAddress ?? "—")
            fact("IPv4", interface.ipv4.map { "\($0.address)/\($0.prefixLength ?? 0)" }.joined(separator: ", "))
            if !interface.ipv6.isEmpty {
                fact("IPv6", interface.ipv6.prefix(2).map(\.address).joined(separator: ", "))
            }
            fact(
                "MTU / speed",
                [interface.mtu.map(String.init), interface.speedLabel].compactMap { $0 }.joined(separator: " · "))
            fact("Traffic", "RX \(interface.rxLabel) · TX \(interface.txLabel)")
            if let wifi = interface.wifiSummary {
                fact("Wi-Fi", wifi)
            }
            if let security = interface.security {
                fact("Security", security)
            }
            if interface.rxErrors + interface.txErrors > 0 {
                fact("Errors", "\(interface.rxErrors + interface.txErrors)")
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 222, maxHeight: 222, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    interface.isPrimary
                        ? Color.blue.opacity(contrast == .increased ? 0.8 : 0.4)
                        : Color.secondary.opacity(contrast == .increased ? 0.4 : 0.12),
                    lineWidth: contrast == .increased ? 2 : 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(interface.displayName), \(interface.statusLabel)")
        .accessibilityValue(
            "IPv4 \(interface.ipv4.map(\.address).joined(separator: ", ")); "
                + "RX \(interface.rxLabel), TX \(interface.txLabel)"
        )
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(value.isEmpty ? "—" : TechnicalLocalizer.localize(value))
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}
