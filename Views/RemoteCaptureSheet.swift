import SwiftUI

struct RemoteCaptureSheet: View {
    let sensor: RemoteSensor
    @Environment(\.dismiss) private var dismiss
    @State private var interfaceName = "en0"
    @State private var duration = 20
    @State private var monitorMode = true
    @State private var filter = ""
    @State private var isCapturing = false
    @State private var errorMessage: String?
    @State private var savedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote capture · \(sensor.name)").font(.headline)
            Text("Runs tcpdump on the remote Mac over SSH. Requires key-based login and passwordless sudo for tcpdump.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Interface", text: $interfaceName)
                Picker("Duration", selection: $duration) {
                    Text("10 seconds").tag(10)
                    Text("20 seconds").tag(20)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                }
                Toggle("Monitor mode / radiotap", isOn: $monitorMode)
                TextField("BPF filter", text: $filter)
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red).textSelection(.enabled)
            }
            if let savedURL {
                Label("Saved \(savedURL.lastPathComponent)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([savedURL]) }
            }
            HStack {
                if isCapturing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start Capture") { start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCapturing)
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func start() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-Remote.pcap"
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isCapturing = true
        errorMessage = nil
        savedURL = nil
        Task {
            do {
                try await RemoteCaptureService.capture(
                    RemoteCaptureRequest(
                        sensor: sensor, interfaceName: interfaceName,
                        duration: duration, monitorMode: monitorMode, filter: filter
                    ),
                    localURL: url
                )
                await MainActor.run {
                    isCapturing = false
                    savedURL = url
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
