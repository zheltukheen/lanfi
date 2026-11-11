import AppKit
import SwiftUI

struct SubnetToolView: View {
    @ObservedObject var model: SubnetToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let subnet = model.result {
                    summary(subnet)
                    details(subnet)
                } else if model.errorMessage == nil {
                    ToolkitEmptyState(
                        icon: "number",
                        title: "Calculate a subnet",
                        message:
                            "CIDR maths for IPv4: network, broadcast, mask, usable range and host count. Works offline."
                    )
                }
            }
            .padding(18)
        }
        .onAppear {
            if model.result == nil { model.calculate() }
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                TextField("CIDR or IP + netmask", text: $model.input)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    .onSubmit { model.calculate() }
                Button("Calculate") { model.calculate() }
                    .buttonStyle(.borderedProminent)
                Button("This Mac") { model.useCurrentNetwork() }
                    .buttonStyle(.bordered)
                Button("Copy") { copy() }
                    .buttonStyle(.bordered)
                    .disabled(model.result == nil)
                Spacer()
                if let subnet = model.result {
                    ToolkitStatusPill(
                        text: String(
                            format: String(localized: "%lld usable hosts"),
                            subnet.usableHosts),
                        tone: .good)
                }
            }
        }
    }

    private func summary(_ subnet: SubnetInfo) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(subnet.cidr)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                    Spacer()
                    Text("/\(subnet.prefixLength)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 14)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ToolkitMetric(title: "Network", value: subnet.network.description)
                    ToolkitMetric(title: "Broadcast", value: subnet.broadcast.description)
                    ToolkitMetric(title: "Netmask", value: subnet.netmask.description)
                    ToolkitMetric(title: "Wildcard", value: subnet.wildcard.description)
                    ToolkitMetric(
                        title: "Usable range",
                        value:
                            "\(subnet.firstUsable?.description ?? "—") – \(subnet.lastUsable?.description ?? "—")"
                    )
                    ToolkitMetric(title: "Usable hosts", value: "\(subnet.usableHosts)")
                }
            }
        }
    }

    private func details(_ subnet: SubnetInfo) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                ToolkitSectionLabel(text: "Details")
                detailRow("Total addresses", "\(subnet.totalAddresses)")
                detailRow("Usable hosts", "\(subnet.usableHosts)")
                detailRow("Prefix length", "/\(subnet.prefixLength)")
                detailRow("Network class", classLabel(subnet))
                Divider()
                Text(
                    "A /31 is treated as a point-to-point link with two usable addresses; a /32 has one."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }

    private func detailRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
        }
    }

    private func classLabel(_ subnet: SubnetInfo) -> String {
        let first = (subnet.network.value >> 24) & 0xff
        switch first {
        case 1...126: return "A"
        case 128...191: return "B"
        case 192...223: return "C"
        case 224...239: return "D (multicast)"
        case 240...255: return "E (reserved)"
        default: return "—"
        }
    }

    private func copy() {
        guard let subnet = model.result else { return }
        let text = """
            LanFi subnet \(subnet.cidr)
            Network: \(subnet.network)
            Broadcast: \(subnet.broadcast)
            Netmask: \(subnet.netmask)
            Wildcard: \(subnet.wildcard)
            Usable: \(subnet.firstUsable?.description ?? "—") – \(subnet.lastUsable?.description ?? "—")
            Hosts: \(subnet.usableHosts)
            """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
