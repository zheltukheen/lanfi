import AppKit
import SwiftUI

struct LANScannerToolView: View {
    @ObservedObject var model: LANScannerToolModel
    @State private var selectedID: String?
    @State private var showingDiscover = false
    @State private var serviceDetails: [String: [UInt16: String]] = [:]
    @State private var detectingDeviceID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if !model.newMACs.isEmpty {
                    newDevicesBanner
                }
                if let result = model.result {
                    summary(result)
                    HStack(alignment: .top, spacing: 14) {
                        devicesTable(result)
                        inspector(result)
                            .frame(width: 240)
                    }
                } else if !model.isScanning {
                    ToolkitEmptyState(
                        icon: "desktopcomputer",
                        title: "Find the devices on this network",
                        message:
                            "ARP sweep plus TCP probes, OUI vendor names and Bonjour host names. Network Guard remembers known devices and flags new ones."
                    )
                }
            }
            .padding(18)
        }
        .onChange(of: model.result) { result in
            if selectedID == nil {
                selectedID = result?.devices.first?.id
            }
        }
        .sheet(isPresented: $showingDiscover) {
            LiveClientDiscoveryView()
        }
    }

    private var controls: some View {
        ToolkitCard {
            HStack(spacing: 10) {
                if model.isScanning {
                    Button("Stop") { model.stop() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Scan") { model.scan() }
                        .buttonStyle(.borderedProminent)
                }
                Toggle("Guard this network", isOn: $model.guardEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text(model.selectedSubnet)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy") { copy() }
                    .buttonStyle(.bordered)
                    .disabled(model.devices.isEmpty)
                Button("Clear") { model.clear() }
                    .buttonStyle(.borderless)
                    .disabled(model.result == nil)
                ToolkitStatusPill(text: statusText, tone: statusTone)
            }
        }
    }

    private var statusText: String {
        if model.isScanning { return String(localized: "Scanning…") }
        guard let result = model.result else { return String(localized: "Ready") }
        let open = result.devices.reduce(0) { $0 + $1.openPorts.count }
        return "\(result.devices.count) devices · \(open) open ports"
    }

    private var statusTone: ToolkitTone {
        if model.isScanning { return .running }
        guard let result = model.result else { return .neutral }
        return result.devices.isEmpty ? .warning : .good
    }

    private var newDevicesBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .foregroundColor(.orange)
            Text(
                "\(model.newMACs.count) new device\(model.newMACs.count == 1 ? "" : "s") since the last guarded scan"
            )
            .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summary(_ result: LANScanResult) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    ToolkitMetric(title: "Devices", value: "\(result.devices.count)")
                    ToolkitMetric(
                        title: "Open ports",
                        value: "\(result.devices.reduce(0) { $0 + $1.openPorts.count })")
                    ToolkitMetric(
                        title: "Named",
                        value: "\(result.devices.filter { $0.hostname != nil }.count)")
                    ToolkitMetric(
                        title: "Gateway",
                        value: result.gateway ?? "—")
                    ToolkitMetric(title: "Interface", value: result.interfaceName)
                    Spacer()
                }
                if result.devices.contains(where: { $0.mac == nil }) {
                    Text(
                        "MAC addresses, vendor names and TCP ports need Local Network access. Grant it in System Settings → Privacy & Security → Local Network, then scan again."
                    )
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
            }
        }
    }

    private func devicesTable(_ result: LANScanResult) -> some View {
        ToolkitCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Devices")
                    Spacer()
                    Text(result.subnet)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(result.devices, selection: $selectedID) {
                    TableColumn("Device") { device in
                        HStack(spacing: 6) {
                            if device.isGateway {
                                Image(systemName: "wifi.router")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                            Text(device.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            if device.isNew {
                                Text("NEW")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    TableColumn("IP") { device in
                        Text(device.ip)
                            .font(.caption.monospaced())
                    }
                    .width(110)
                    TableColumn("Vendor") { device in
                        Text(device.vendor ?? "—")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .width(120)
                    TableColumn("MAC") { device in
                        Text(device.mac ?? "—")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                    .width(130)
                    TableColumn("Open ports") { device in
                        Text(
                            device.openPorts.isEmpty
                                ? "—"
                                : device.openPorts.prefix(4).map(String.init).joined(separator: ",")
                        )
                        .font(.caption2.monospacedDigit())
                    }
                    .width(120)
                    TableColumn("Latency") { device in
                        Text(ToolkitFormat.milliseconds(device.latencyMilliseconds))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(70)
                }
                .frame(height: min(CGFloat(result.devices.count) * 26 + 60, 520))
            }
        }
    }

    private func inspector(_ result: LANScanResult) -> some View {
        let device = result.devices.first { $0.id == selectedID } ?? result.devices.first
        return ToolkitCard {
            VStack(alignment: .leading, spacing: 9) {
                ToolkitSectionLabel(text: "Device")
                if let device {
                    Text(device.displayName)
                        .font(.headline)
                    Text(device.ip)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                    if device.isGateway {
                        Text("Gateway")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    if device.isThisMac {
                        Text("This Mac")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: Capsule())
                    }
                    Divider()
                    inspectorRow("Vendor", device.vendor ?? "—")
                    inspectorRow("Hostname", device.hostname ?? "—")
                    inspectorRow("MAC", device.mac ?? "—")
                    inspectorRow(
                        "Latency", ToolkitFormat.milliseconds(device.latencyMilliseconds))
                    Divider()
                    ToolkitSectionLabel(text: "Open ports")
                    if device.openPorts.isEmpty {
                        Text("None of the probed ports answered.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(device.openPorts, id: \.self) { port in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text("\(port)/tcp")
                                        .font(.caption.monospacedDigit())
                                    Text(PortServices.name(for: port) ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                if let detail = serviceDetails[device.id]?[port] {
                                    Text(detail)
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        if !device.openPorts.isEmpty {
                            Button {
                                detectVersions(for: device)
                            } label: {
                                if detectingDeviceID == device.id {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Detect versions", systemImage: "tag")
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .disabled(detectingDeviceID != nil)
                        }
                    }
                } else {
                    Text("Select a device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Divider()
                Button {
                    showingDiscover = true
                } label: {
                    Label("Discover Wi-Fi clients…", systemImage: "person.3")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Text("Frame-level Wi-Fi clients use monitor capture; this scanner uses ARP, Bonjour and TCP.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func detectVersions(for device: LANDevice) {
        guard detectingDeviceID == nil else { return }
        detectingDeviceID = device.id
        let ports = device.openPorts
        Task {
            var detected: [UInt16: String] = [:]
            await withTaskGroup(of: (UInt16, String?).self) { group in
                for port in ports {
                    group.addTask {
                        let banner = await ServiceBannerProbe().probe(
                            host: device.ip, port: port)
                        return (port, banner)
                    }
                }
                for await (port, banner) in group {
                    if let banner { detected[port] = banner }
                }
            }
            serviceDetails[device.id] = detected
            detectingDeviceID = nil
        }
    }

    private func copy() {
        guard let result = model.result else { return }
        var lines = ["LanFi LAN scan \(result.subnet) · \(result.interfaceName)", ""]
        for device in result.devices {
            lines.append(
                "\(device.ip)\t\(device.mac ?? "-")\t\(device.vendor ?? "-")\t\(device.openPorts.map(String.init).joined(separator: ","))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
