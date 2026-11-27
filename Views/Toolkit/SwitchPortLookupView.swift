import LanFiCore
import SwiftUI

/// G15: asks a switch where a scanned MAC was learned. The sheet reads only —
/// BRIDGE-MIB/Q-BRIDGE forwarding tables and LLDP neighbours — and keeps the
/// community in memory for this one read.
struct SwitchPortLookupView: View {
    let device: LANDevice?
    let gateway: String?
    let onResult: (SwitchInventory, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host: String
    @State private var community = "public"
    @State private var isReading = false
    @State private var inventory: SwitchInventory?
    @State private var errorMessage: String?
    @State private var onlyThisDevice: Bool

    init(
        device: LANDevice?, gateway: String?,
        onResult: @escaping (SwitchInventory, String) -> Void
    ) {
        self.device = device
        self.gateway = gateway
        self.onResult = onResult
        _host = State(initialValue: gateway ?? "")
        _onlyThisDevice = State(initialValue: device?.mac != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
            AppSheetHeader(
                icon: "switch.2",
                title: "Switch port lookup",
                subtitle:
                    "Map a MAC from this scan to the switch port and VLAN it was learned on. Read-only SNMP v2c; the community is used for this read and is never stored."
            ) {
                Button("Close") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.large) {
                    form
                    if let errorMessage {
                        ToolkitErrorBanner(message: errorMessage)
                    }
                    if let inventory {
                        resultCard(inventory)
                    }
                }
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 460)
    }

    private var form: some View {
        AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                SectionLabel(text: "Switch")
                HStack(spacing: DesignToken.Spacing.small) {
                    TextField("Switch address", text: $host)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Community", text: $community)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                    AppButton(
                        "Read switch", systemImage: "arrow.down.doc", tone: .primary,
                        isBusy: isReading,
                        isEnabled: !isReading && !host.isEmpty && !community.isEmpty
                    ) {
                        read()
                    }
                }
                Text(
                    "Reads the BRIDGE-MIB and Q-BRIDGE forwarding tables plus LLDP neighbours. Nothing is written to the switch."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let device {
                    Text(
                        String(
                            format: String(localized: "Looking for %@ (%@)"),
                            device.displayName, device.mac ?? device.ip)
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func resultCard(_ inventory: SwitchInventory) -> some View {
        let bridge = inventory.bridge
        let match = device.flatMap { device -> SwitchPortEntry? in
            guard let mac = device.mac else { return nil }
            return bridge.port(forMAC: mac)
        }
        let rows = filteredPorts(inventory)
        return AppCard {
            VStack(alignment: .leading, spacing: DesignToken.Spacing.small) {
                HStack {
                    SectionLabel(text: "Forwarding table")
                    Spacer()
                    ToolkitStatusPill(
                        text: String(
                            format: String(localized: "%lld ports · %lld VLANs"),
                            bridge.ports.count, bridge.vlanNames.count), tone: .good)
                }
                if let device {
                    if let match {
                        Text(
                            String(
                                format: String(localized: "Learned on %@"),
                                locationLine(match, in: inventory))
                        )
                        .font(.callout.weight(.semibold))
                        if let uplink = inventory.uplinkDescription(for: match) {
                            Text(String(format: String(localized: "Uplink: %@"), uplink))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if device.mac != nil {
                        Text(
                            "Not in this switch's forwarding table. It may be behind another switch, on Wi-Fi, or silent right now."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        Text("This device has no MAC address, so it cannot be placed on a port.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if match != nil {
                    Toggle("Only this device", isOn: $onlyThisDevice)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                AppTable(
                    columns: columns(inventory), rows: rows, initialKey: "port"
                )
                .frame(height: ToolkitTableHeight.rows(rows.count, row: 26))
                .appTableSurface(cornerRadius: DesignToken.Radius.card)
            }
        }
    }

    private func filteredPorts(_ inventory: SwitchInventory) -> [SwitchPortEntry] {
        guard onlyThisDevice, let mac = device?.mac,
            let key = BridgeMIB.normalizedMAC(mac)
        else { return inventory.bridge.ports }
        let matches = inventory.bridge.ports.filter { $0.mac == key }
        return matches.isEmpty ? inventory.bridge.ports : matches
    }

    private func columns(_ inventory: SwitchInventory) -> [AppTableColumn<SwitchPortEntry>] {
        [
            AppTableColumn(
                id: "port", title: "Port", minWidth: 130,
                value: { .text($0.portLabel) }
            ) { entry in
                Text(entry.portLabel)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            },
            AppTableColumn(
                id: "vlan", title: "VLAN", minWidth: 60,
                value: { .number($0.vlan) }
            ) { entry in
                Text(entry.vlan.map(String.init) ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            },
            AppTableColumn(
                id: "mac", title: "MAC address", minWidth: 150,
                value: { .text($0.mac) }
            ) { entry in
                Text(entry.mac)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            },
            AppTableColumn(
                id: "uplink", title: "Uplink", minWidth: 150,
                value: { .text(inventory.uplinkDescription(for: $0)) }
            ) { entry in
                Text(inventory.uplinkDescription(for: entry) ?? "—")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            },
        ]
    }

    private func locationLine(_ entry: SwitchPortEntry, in inventory: SwitchInventory) -> String {
        var parts = [entry.portLabel]
        if let vlan = entry.vlan {
            if let name = inventory.bridge.vlanName(vlan) {
                parts.append("VLAN \(vlan) · \(name)")
            } else {
                parts.append("VLAN \(vlan)")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func read() {
        guard !isReading else { return }
        isReading = true
        errorMessage = nil
        let address = host.trimmingCharacters(in: .whitespaces)
        let community = community
        Task {
            do {
                let read = try await SwitchInventoryService().read(
                    host: address, community: community)
                inventory = read
                onResult(read, address)
            } catch {
                errorMessage = error.localizedDescription
            }
            isReading = false
        }
    }
}
