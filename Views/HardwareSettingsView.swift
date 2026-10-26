import SwiftUI

struct HardwareSettingsView: View {
    @State private var devices: [DetectedHardware] = []
    @State private var scanning = false

    var body: some View {
        Form {
            Section("Detected hardware") {
                if scanning {
                    ProgressView("Scanning USB devices…")
                } else if devices.isEmpty {
                    Text("No spectrum analyzer, WLAN Pi, SDR or 802.15.4 adapter detected.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(devices) { device in
                        LabeledContent(device.name) {
                            Text(device.category).foregroundColor(.secondary)
                        }
                    }
                }
                Button("Scan USB Hardware") { refresh() }
                    .disabled(scanning)
            }

            Section("Integration status") {
                Text(
                    "LanFi detects supported USB hardware, but native spectrum/Zigbee capture requires the vendor driver and API. Wi-Fi scanning uses CoreWLAN."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                Text("Remote Mac sensors are supported separately over SSH in Tools → Remote Sensors.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear { if devices.isEmpty { refresh() } }
    }

    private func refresh() {
        scanning = true
        Task {
            let detected = await Task.detached(priority: .utility) {
                await HardwareInventory.detect()
            }.value
            await MainActor.run {
                devices = detected
                scanning = false
            }
        }
    }
}
