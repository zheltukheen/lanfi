import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            VStack(spacing: 3) {
                Text("LanFi")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Native macOS Wi‑Fi diagnostician")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("Version \(version) (\(build))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                aboutRow("waveform.path.ecg", "Quality, channel and security analysis")
                aboutRow("network", "Wi-Fi, Ethernet, VPN, bridge and loopback interfaces")
                aboutRow("stethoscope", "Diagnostics with monitoring and history")
                aboutRow("map", "IDW survey heatmaps, walls and PDF reports")
                aboutRow("terminal", "CLI, deep links and offline pcap analysis")
                aboutRow("lock.shield", "Local-only, no telemetry or account")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/zheltukheen/wifa")!)
                Link("Releases", destination: URL(string: "https://github.com/zheltukheen/wifa/releases")!)
                Link("Documentation", destination: URL(string: "https://github.com/zheltukheen/wifa#readme")!)
            }
            .font(.caption)

            VStack(spacing: 2) {
                Text("© 2025–2026 zheltukheen and LanFi contributors")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Ad-hoc signed build · notarization requires an Apple Developer account")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(26)
        .frame(width: 430, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func aboutRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 18)
            Text(text).font(.caption)
        }
    }
}
