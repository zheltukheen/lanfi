import SwiftUI

struct HardwareSettingsView: View {
    @State private var devices: [DetectedHardware] = []
    @State private var scanning = false
    @StateObject private var ble = BLEScanner()
    @State private var ssdpDevices: [(ip: String, ad: LANAdvertisement)] = []
    @State private var snmpHost = ""
    @State private var snmpCommunity = "public"
    @State private var snmpValues: [String: SNMPValue] = [:]
    @State private var snmpError: String?
    @State private var ssdpBusy = false
    @State private var snmpBusy = false

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

            Section("Router / NAS") {
                HStack {
                    Button(ssdpBusy ? "Discovering…" : "Discover with SSDP") {
                        ssdpBusy = true
                        ssdpDevices = []
                        Task {
                            let found = await SSDPDiscovery.advertisements(timeout: 2)
                            await MainActor.run {
                                ssdpDevices = found.map { (ip: $0.key, ad: $0.value) }
                                    .sorted { $0.ip < $1.ip }
                                ssdpBusy = false
                                if snmpHost.isEmpty, let first = ssdpDevices.first?.ip {
                                    snmpHost = first
                                }
                            }
                        }
                    }
                    .disabled(ssdpBusy)
                    Spacer()
                    if ssdpBusy { ProgressView().controlSize(.small) }
                }
                ForEach(ssdpDevices.indices, id: \.self) { index in
                    let device = ssdpDevices[index]
                    LabeledContent(device.ip) {
                        Text(
                            [device.ad.name, device.ad.model, device.ad.manufacturer]
                                .compactMap { $0 }.joined(separator: " · ")
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    TextField("Router address", text: $snmpHost)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Community", text: $snmpCommunity)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    Button(snmpBusy ? "Reading…" : "Read SNMP") { readSNMP() }
                        .disabled(snmpBusy || snmpHost.isEmpty)
                }
                if let snmpError {
                    Text(snmpError).font(.caption2).foregroundColor(.red)
                }
                let name = snmpValues[SNMPOID.systemName]?.text
                if let name, !name.isEmpty {
                    LabeledContent("Device", value: name)
                }
                ForEach(snmpCounterRows.indices, id: \.self) { index in
                    let row = snmpCounterRows[index]
                    LabeledContent(row.0) { Text(row.1).font(.caption.monospacedDigit()) }
                }
                Text(
                    "Read-only SNMP v2c GET of standard interface counters, plus one bounded SSDP discovery. The community is used for this request only and is never stored."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Section("BLE beacons") {
                HStack {
                    Button(ble.isScanning ? "Stop Scan" : "Scan for Beacons") {
                        if ble.isScanning { ble.stop() } else { ble.start() }
                    }
                    Button("Clear") { ble.clear() }
                        .disabled(ble.beacons.isEmpty)
                    Spacer()
                    Text(ble.stateText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if ble.beacons.isEmpty {
                    Text(
                        "iBeacon and Eddystone advertisements are decoded locally. Scanning is passive: LanFi never connects to or writes to the device."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                } else {
                    ForEach(ble.beacons) { beacon in
                        HStack(spacing: 8) {
                            Text(beacon.name.isEmpty ? String(beacon.id.prefix(8)) : beacon.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(beacon.detail)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                Text("\(beacon.kind.label) · \(beacon.rssi) dBm")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Text(
                    "Zigbee is analysed as 2.4 GHz coexistence (quiet channels: \(ZigbeeCoexistence.quietChannels.map(String.init).joined(separator: ", "))); LanFi does not drive an 802.15.4 adapter."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
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
        .padding(DesignToken.Spacing.medium)
        .onAppear { if devices.isEmpty { refresh() } }
    }

    private var snmpCounterRows: [(String, String)] {
        [
            ("sysDescr", snmpValues[SNMPOID.systemDescription]?.text ?? ""),
            ("ifInOctets", snmpValues[SNMPOID.interfaceInOctets]?.text ?? ""),
            ("ifOutOctets", snmpValues[SNMPOID.interfaceOutOctets]?.text ?? ""),
        ].filter { !$0.1.isEmpty }
    }

    private func readSNMP() {
        snmpBusy = true
        snmpError = nil
        snmpValues = [:]
        Task {
            do {
                let values = try await SNMPClient.get(
                    host: snmpHost, community: snmpCommunity)
                await MainActor.run {
                    snmpValues = values
                    snmpBusy = false
                }
            } catch {
                await MainActor.run {
                    snmpError = error.localizedDescription
                    snmpBusy = false
                }
            }
        }
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
