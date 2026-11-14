import SwiftUI

struct LiveClientDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var interfaces: [String] = []
    @State private var selectedInterface = "en0"
    @State private var isCapturing = false
    @State private var clients: [CapturedClient] = []
    @State private var selectedBSSID = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover clients").font(.headline)
                    Text("Short monitor capture, then MAC extraction. CoreWLAN cannot list clients live.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            HStack {
                Picker("Interface", selection: $selectedInterface) {
                    ForEach(interfaces, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 180)
                Picker("Network", selection: $selectedBSSID) {
                    Text("All networks").tag("")
                    ForEach(bssids, id: \.self) { bssid in
                        Text(bssid).tag(bssid)
                    }
                }
                .frame(width: 220)
                .disabled(clients.isEmpty)
                Button("Capture 10 seconds") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing || interfaces.isEmpty)
                if isCapturing { ProgressView().controlSize(.small) }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red).textSelection(.enabled)
            }
            if clients.isEmpty {
                Text(
                    "No client frames yet. Built-in Apple adapters often deliver zero monitor frames; use an external adapter."
                )
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredClients) {
                    TableColumn("MAC", value: \.mac)
                    TableColumn("Vendor") { client in
                        Text(OUIParser.vendor(for: client.mac)).lineLimit(1)
                    }
                    .width(150)
                    TableColumn("BSSID", value: \.bssid)
                    TableColumn("Frames") { Text("\($0.frameCount)") }.width(55)
                    TableColumn("Mgmt/Data") { Text("\($0.managementFrames)/\($0.dataFrames)") }.width(80)
                    TableColumn("RSSI") { Text($0.rssi.map { "\($0) dBm" } ?? "—") }.width(65)
                    TableColumn("EAPOL") { Text($0.eapolFrames == 0 ? "—" : "\($0.eapolFrames)") }.width(50)
                    TableColumn("Probes") { client in
                        Text(client.probeSSIDs.isEmpty ? "—" : client.probeSSIDs.joined(separator: ", "))
                            .lineLimit(1)
                            .help(client.probeSSIDs.joined(separator: "\n"))
                    }
                    .width(160)
                }
            }
        }
        .padding(16)
        .frame(width: 800, height: 460)
        .onAppear {
            interfaces = LiveCaptureService.interfaceNames()
            if let first = interfaces.first { selectedInterface = first }
        }
    }

    private var bssids: [String] {
        Array(Set(clients.map(\.bssid))).sorted()
    }

    private var filteredClients: [CapturedClient] {
        guard !selectedBSSID.isEmpty else { return clients }
        return clients.filter { $0.bssid == selectedBSSID }
    }

    private func start() {
        isCapturing = true
        errorMessage = nil
        clients = []
        selectedBSSID = ""
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanfi-clients-\(UUID().uuidString).pcap")
        let options = LiveCaptureOptions(
            interfaceName: selectedInterface, duration: 10, outputURL: url, monitorMode: true
        )
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try await LiveCaptureService.capture(options)
                }.value
                let data = try Data(contentsOf: url)
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.clients(data: data)
                }.value
                await MainActor.run {
                    isCapturing = false
                    clients = parsed
                    if parsed.isEmpty { errorMessage = "Capture contained no client frames." }
                }
            } catch {
                await MainActor.run {
                    isCapturing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
