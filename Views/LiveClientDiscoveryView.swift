import SwiftUI

struct LiveClientDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var interfaces: [String] = []
    @State private var selectedInterface = "en0"
    @State private var isCapturing = false
    @State private var clients: [CapturedClient] = []
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
                .frame(width: 200)
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
                Table(clients) {
                    TableColumn("MAC", value: \.mac)
                    TableColumn("BSSID", value: \.bssid)
                    TableColumn("Frames") { Text("\($0.frameCount)") }.width(60)
                }
            }
        }
        .padding(16)
        .frame(width: 560, height: 420)
        .onAppear {
            interfaces = LiveCaptureService.interfaceNames()
            if let first = interfaces.first { selectedInterface = first }
        }
    }

    private func start() {
        isCapturing = true
        errorMessage = nil
        clients = []
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
