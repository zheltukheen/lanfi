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
                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "mac", title: "MAC", minWidth: 120,
                            value: { .text($0.mac) }
                        ) { Text($0.mac).font(.caption.monospaced()) },
                        AppTableColumn(
                            id: "vendor", title: "Vendor", minWidth: 140,
                            value: { .text(OUIParser.vendor(for: $0.mac)) }
                        ) { client in
                            Text(OUIParser.vendor(for: client.mac)).lineLimit(1)
                        },
                        AppTableColumn(
                            id: "bssid", title: "BSSID", minWidth: 130,
                            value: { .text($0.bssid) }
                        ) { Text($0.bssid).font(.caption.monospaced()) },
                        AppTableColumn(
                            id: "frames", title: "Frames", minWidth: 60,
                            value: { .number($0.frameCount) }
                        ) { Text("\($0.frameCount)") },
                        AppTableColumn(
                            id: "mgmtData", title: "Mgmt/Data", minWidth: 80,
                            value: { .number($0.dataFrames) }
                        ) { Text("\($0.managementFrames)/\($0.dataFrames)") },
                        AppTableColumn(
                            id: "rssi", title: "RSSI", minWidth: 60,
                            value: { .number($0.rssi) }
                        ) { Text($0.rssi.map { "\($0) dBm" } ?? "—") },
                        AppTableColumn(
                            id: "eapol", title: "EAPOL", minWidth: 60,
                            value: { .number($0.eapolFrames) }
                        ) { Text($0.eapolFrames == 0 ? "—" : "\($0.eapolFrames)") },
                        AppTableColumn(
                            id: "probes", title: "Probes", minWidth: 160,
                            value: { .text($0.probeSSIDs.joined(separator: ", ")) }
                        ) { client in
                            Text(
                                client.probeSSIDs.isEmpty
                                    ? "—" : client.probeSSIDs.joined(separator: ", ")
                            )
                            .lineLimit(1)
                            .help(client.probeSSIDs.joined(separator: "\n"))
                        },
                    ],
                    rows: filteredClients, initialKey: "frames", ascending: false
                )
                .appTableSurface()
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidthWide, minHeight: 460)
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
                let data = try PcapAnalyzer.mappedData(at: url)
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
