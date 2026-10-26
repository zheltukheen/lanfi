import SwiftUI
import UniformTypeIdentifiers

struct OfflineCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    private let initialURL: URL?
    @State private var beacons: [CapturedBeacon] = []
    @State private var fileName = ""
    @State private var errorMessage: String?
    @State private var isParsing = false

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline packet analysis")
                        .font(.title3.bold())
                    Text("Open a pcap or pcapng capture with radiotap or 802.11 frames.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Open Capture…") { open() }
                Button("Close") { dismiss() }
            }
            .padding(14)
            Divider()

            if isParsing {
                ProgressView("Parsing capture…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else if beacons.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.35))
                    Text("No capture loaded")
                        .font(.headline)
                    Text("Beacons and probe responses from monitor-mode captures are decoded offline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Capture…") { open() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(fileName).font(.caption.bold())
                        Text("· \(beacons.count) BSSIDs").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("Export CSV…") { exportCSV() }
                            .controlSize(.small)
                    }
                    .padding(10)
                    Table(beacons) {
                        TableColumn("SSID", value: \.ssid)
                        TableColumn("BSSID", value: \.bssid)
                        TableColumn("Ch") { Text($0.channel.map(String.init) ?? "—") }.width(40)
                        TableColumn("RSSI") { Text($0.rssi.map { "\($0) dBm" } ?? "—") }.width(70)
                        TableColumn("Security", value: \.security)
                        TableColumn("IEs") { Text("\($0.informationElements.count)") }.width(40)
                        TableColumn("Clients") { Text($0.clientCount.map(String.init) ?? "—") }.width(55)
                        TableColumn("EHT") { Text($0.isEHT ? "Yes" : "—") }.width(40)
                    }
                    .tableStyle(.inset)
                }
            }
        }
        .frame(width: 840, height: 520)
        .task {
            if let initialURL { load(initialURL) }
        }
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.title = "Open packet capture"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pcap") ?? .data,
            UTType(filenameExtension: "pcapng") ?? .data,
            UTType(filenameExtension: "cap") ?? .data,
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        isParsing = true
        errorMessage = nil
        beacons = []
        Task {
            do {
                let data = try Data(contentsOf: url)
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.parse(data: data)
                }.value
                await MainActor.run {
                    isParsing = false
                    fileName = url.lastPathComponent
                    beacons = parsed
                    if parsed.isEmpty { errorMessage = "No beacons or probe responses found." }
                }
            } catch {
                await MainActor.run {
                    isParsing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-Capture.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines = ["ssid,bssid,channel,rssi,security,eht"]
        for item in beacons {
            let ssid = item.ssid.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append(
                "\"\(ssid)\",\(item.bssid),\(item.channel.map(String.init) ?? ""),"
                    + "\(item.rssi.map(String.init) ?? ""),\"\(item.security)\",\(item.isEHT)"
            )
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
