import SwiftUI

/// Network Monitor already exists as the Interfaces tab in the main window.
/// This screen links to it and shows a read-only summary instead of a second
/// copy of the full table.
struct NetworkMonitorLinkToolView: View {
    @ObservedObject var interfaces: InterfacesViewModel
    let open: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ToolkitCard {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36))
                            .foregroundColor(.accentColor)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Network Monitor")
                                .font(.title3.bold())
                            Text(
                                "Interfaces, addresses, gateway, DNS and VPN tunnels already live in the main window. The toolkit opens that screen instead of keeping a second copy."
                            )
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Button {
                                open()
                            } label: {
                                Label("Open Network Monitor", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                }

                if !interfaces.report.interfaces.isEmpty {
                    summary
                }
            }
            .padding(18)
        }
        .task {
            if interfaces.report.interfaces.isEmpty {
                await interfaces.refresh()
            }
        }
    }

    private var summary: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                ToolkitSectionLabel(text: "Current snapshot")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ToolkitMetric(
                        title: "Interfaces", value: "\(interfaces.report.interfaces.count)")
                    ToolkitMetric(
                        title: "Up", value: "\(interfaces.report.upCount)")
                    ToolkitMetric(
                        title: "Primary", value: interfaces.report.primaryInterface ?? "—")
                    ToolkitMetric(title: "Router", value: interfaces.report.router ?? "—")
                    ToolkitMetric(
                        title: "DNS",
                        value: interfaces.report.dnsServers.first ?? "—")
                    ToolkitMetric(
                        title: "Tunnels", value: "\(interfaces.report.tunnelCount)")
                }
                Text("This summary is read-only. Use the main window for counters, addresses and per-interface detail.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
