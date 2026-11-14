import SwiftUI

/// Network Monitor overview. It leads with the one interface that actually
/// carries traffic and keeps every other interface collapsed until it is
/// needed, so the screen answers "how am I connected?" before it becomes a
/// wall of counters.
struct InterfacesView: View {
    @ObservedObject var interfaces: InterfacesViewModel
    @State private var showInactive = false

    private var activeInterfaces: [SystemInterface] {
        interfaces.report.interfaces.filter { item in
            item.isUp && (item.isPrimary || !item.ipv4.isEmpty || !item.ipv6.isEmpty || item.kind == .wifi)
        }
    }

    private var inactiveInterfaces: [SystemInterface] {
        interfaces.report.interfaces.filter { !activeInterfaces.contains($0) }
    }

    private var primaryInterface: SystemInterface? {
        interfaces.report.interfaces.first(where: \.isPrimary) ?? activeInterfaces.first
    }

    private var otherActive: [SystemInterface] {
        activeInterfaces.filter { $0.id != primaryInterface?.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if interfaces.report.interfaces.isEmpty {
                    emptyState
                } else {
                    if let primaryInterface {
                        PrimaryInterfaceCard(
                            interface: primaryInterface,
                            report: interfaces.report
                        )
                    }
                    if !otherActive.isEmpty {
                        sectionLabel(
                            String(
                                format: String(localized: "Other active interfaces (%lld)"),
                                otherActive.count))
                        VStack(spacing: 6) {
                            ForEach(otherActive) { item in
                                CompactInterfaceRow(interface: item)
                            }
                        }
                    }
                    if !inactiveInterfaces.isEmpty {
                        DisclosureGroup(isExpanded: $showInactive) {
                            VStack(spacing: 6) {
                                ForEach(inactiveInterfaces) { item in
                                    CompactInterfaceRow(interface: item)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.slash")
                                    .font(.caption2)
                                Text(
                                    String(
                                        format: String(localized: "Inactive interfaces (%lld)"),
                                        inactiveInterfaces.count)
                                )
                                .font(.caption.weight(.medium))
                                Spacer()
                            }
                            .foregroundColor(.secondary)
                            .contentShape(Rectangle())
                        }
                        .padding(.horizontal, 2)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Network interfaces")
                    .font(.headline)
                Text(
                    String(
                        format: String(localized: "%lld up · %lld tunnels · updated %@"),
                        interfaces.report.upCount,
                        interfaces.report.tunnelCount,
                        interfaces.lastUpdatedText)
                )
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
                    Image(systemName: "arrow.clockwise")
                }
            }
            .controlSize(.small)
            .disabled(interfaces.isScanning)
            .help("Refresh")
            Button {
                interfaces.copyReport()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copy interface report")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
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

// MARK: - Primary interface

private struct PrimaryInterfaceCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let interface: SystemInterface
    let report: InterfacesReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: interface.kind.systemImage)
                    .font(.system(size: 18))
                    .foregroundColor(interface.isUp ? .accentColor : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(interface.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(interface.kind.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(interface.bsdName)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusPill
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ipv4Text)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                if let ipv6 = interface.primaryIPv6 {
                    Text(ipv6)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            Divider()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                alignment: .leading,
                spacing: 6
            ) {
                fact("Router", report.router ?? interface.router ?? "—")
                fact("DNS", report.dnsServers.first ?? interface.dnsServers.first ?? "—")
                if let wifi = interface.wifiSummary {
                    fact("Wi-Fi", wifi)
                }
                if let security = interface.security {
                    fact("Security", security)
                }
                fact("MAC", interface.macAddress ?? "—")
                fact(
                    "Link",
                    [interface.mtu.map { "MTU \($0)" }, interface.speedLabel]
                        .compactMap { $0 }.joined(separator: " · "))
                fact("Traffic", "RX \(interface.rxLabel) · TX \(interface.txLabel)")
                if interface.rxErrors + interface.txErrors > 0 {
                    fact("Errors", "\(interface.rxErrors + interface.txErrors)")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    Color.blue.opacity(contrast == .increased ? 0.8 : 0.25),
                    lineWidth: contrast == .increased ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var ipv4Text: String {
        guard let address = interface.primaryIPv4 else { return "—" }
        return "\(address)/\(interface.ipv4.first?.prefixLength ?? 0)"
    }

    private var statusPill: some View {
        Text(interface.statusLabel)
            .font(.caption2.weight(.semibold))
            .foregroundColor(interface.isUp ? .green : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                (interface.isUp ? Color.green : Color.secondary).opacity(0.10),
                in: Capsule())
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value.isEmpty ? "—" : TechnicalLocalizer.localize(value))
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Secondary interfaces

private struct CompactInterfaceRow: View {
    let interface: SystemInterface

    var body: some View {
        DisclosureGroup {
            InterfaceFacts(interface: interface)
                .padding(.top, 7)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: interface.kind.systemImage)
                    .font(.caption)
                    .foregroundColor(interface.isUp ? .accentColor : .secondary)
                    .frame(width: 16)
                Text(interface.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(interface.kind.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if interface.isPrimary {
                    Text("PRIMARY")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(shortAddress)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Circle()
                    .fill(interface.isUp ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1))
    }

    private var shortAddress: String {
        if let ipv4 = interface.primaryIPv4 {
            return ipv4
        }
        if let ipv6 = interface.primaryIPv6 {
            return String(ipv6.prefix(18)) + (ipv6.count > 18 ? "…" : "")
        }
        return interface.statusLabel
    }
}

private struct InterfaceFacts: View {
    let interface: SystemInterface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("Type", interface.kind.title)
            fact("MAC", interface.macAddress ?? "—")
            fact(
                "IPv4",
                interface.ipv4.map { "\($0.address)/\($0.prefixLength ?? 0)" }
                    .joined(separator: ", "))
            if !interface.ipv6.isEmpty {
                fact("IPv6", interface.ipv6.prefix(2).map(\.address).joined(separator: ", "))
            }
            fact(
                "MTU / speed",
                [interface.mtu.map(String.init), interface.speedLabel]
                    .compactMap { $0 }.joined(separator: " · "))
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
    }

    private func fact(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(value.isEmpty ? "—" : TechnicalLocalizer.localize(value))
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
