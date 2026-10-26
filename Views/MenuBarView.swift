import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    @ObservedObject var diagnostics: DiagnosticsViewModel
    @Environment(\.openWindow) private var openWindow

    private var statusColor: Color {
        switch diagnostics.overall {
        case .pass: return .green
        case .warning: return .orange
        case .fail: return .red
        default: return .gray
        }
    }

    private var connected: NetworkModel? {
        guard let bssid = viewModel.currentConnectedBSSID else { return nil }
        return viewModel.networks.first { $0.bssid == bssid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.menuBarAlerts.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(viewModel.menuBarAlerts.prefix(3)) { alert in
                        HStack(alignment: .top, spacing: 6) {
                            Image(
                                systemName: alert.severity == .critical
                                    ? "exclamationmark.triangle.fill"
                                    : alert.severity == .warning ? "exclamationmark.circle.fill" : "info.circle.fill"
                            )
                            .foregroundColor(
                                alert.severity == .critical
                                    ? .red : alert.severity == .warning ? .orange : .blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(alert.title).font(.caption.bold())
                                Text(alert.detail)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .firstTextBaseline) {
                Text("LanFi")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.networks.count) networks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let connected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(connected.displaySSID)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text("\(connected.signal) dBm · Ch \(connected.channel) · \(connected.bandLabel)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(viewModel.metrics(for: connected)?.qualityScore ?? 0)")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Not connected to a Wi-Fi network")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text("Diagnostics: \(diagnostics.overall.label)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Run") {
                    Task { await diagnostics.run() }
                }
                .controlSize(.mini)
                .disabled(diagnostics.isRunning)
            }

            if let best = viewModel.analysis.bestChannel(for: .band5) {
                Text("Recommended 5 GHz: channel \(best.channel) · \(best.widthMHz) MHz")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open LanFi", systemImage: "macwindow")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit LanFi", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
    }
}
