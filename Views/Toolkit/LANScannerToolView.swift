import AppKit
import SwiftUI

struct LANScannerToolView: View {
    @ObservedObject var model: LANScannerToolModel
    @State private var selectedID: String?
    @State private var showingDiscover = false
    @State private var serviceDetails: [String: [UInt16: String]] = [:]
    @State private var detectingDeviceID: String?
    @AppStorage("LanFi.lanScannerTab") private var tabRaw = 0
    @StateObject private var shelf = DeviceShelfViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("View", selection: $tabRaw) {
                    Text("Scan").tag(0)
                    Text("Devices").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Text(
                    "The shelf keeps every device, its name, ports, availability and history across scans."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if tabRaw == 0 {
                scanContent
            } else {
                DeviceShelfView(model: shelf)
            }
        }
        .onAppear {
            LocalNetworkAccess.request()
            applyPendingShelfLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanfiSelectShelfDevice)) { _ in
            applyPendingShelfLink()
        }
        .onChange(of: model.result) { result in
            // A new scan replaces the device list, so cached service banners
            // from the previous scan would belong to stale IPs.
            serviceDetails.removeAll()
            if selectedID == nil
                || result?.devices.contains(where: { $0.id == selectedID }) != true
            {
                selectedID = result?.devices.first?.id
            }
            if let result {
                shelf.merge(result)
            }
        }
        .sheet(isPresented: $showingDiscover) {
            LiveClientDiscoveryView()
        }
    }

    /// A `lanfi://device/<tag>` link (from a printed QR label) opens the shelf
    /// on that device.
    private func applyPendingShelfLink() {
        guard let tag = DeviceShelfLink.pendingTag else { return }
        DeviceShelfLink.pendingTag = nil
        tabRaw = 1
        if let device = shelf.device(assetTag: tag) {
            shelf.selectedID = device.id
        }
    }

    private var scanContent: some View {
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
                            "ARP plus a fast ICMP sweep, TCP probes, Bonjour, SSDP/UPnP and reverse DNS. LanFi fills in names, models, services and roles, not just addresses. Network Guard remembers known devices and flags new ones."
                    )
                }
            }
            .padding(18)
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
        return String(
            format: String(localized: "%lld devices · %lld open ports"),
            result.devices.count, open)
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
                String(
                    format: String(localized: "%lld new devices since the last guarded scan"),
                    model.newMACs.count)
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
                        title: "Identified",
                        value:
                            "\(result.devices.filter { $0.hostname != nil || $0.model != nil || !$0.services.isEmpty }.count)"
                    )
                    ToolkitMetric(
                        title: "Gateway",
                        value: result.gateway ?? "—")
                    ToolkitMetric(title: "Interface", value: result.interfaceName)
                    Spacer()
                }
                if result.localNetworkAccessLikelyDenied || result.devices.contains(where: { $0.mac == nil }) {
                    localNetworkGate
                }
            }
        }
    }

    private var localNetworkGate: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.orange)
                Text("Local Network access is off")
                    .font(.caption.weight(.semibold))
            }
            Text(
                "macOS hides the ARP table, vendor names and host names without this permission, so the sweep can only return bare addresses. Allow LanFi under Privacy & Security → Local Network, then rescan."
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open Settings") { LocalNetworkAccess.openSettings() }
                    .controlSize(.small)
                Button("Request access") { LocalNetworkAccess.request() }
                    .controlSize(.small)
                Button("Rescan") { model.scan() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanning)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
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
                    .width(105)
                    TableColumn("Type") { device in
                        Text(device.kindLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(120)
                    TableColumn("Make / model") { device in
                        Text(
                            [device.makeLabel, device.model]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty && $0 != "—" }
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                    TableColumn("Services") { device in
                        Text(
                            device.serviceSummary.isEmpty
                                ? "—"
                                : device.serviceSummary.prefix(2).joined(separator: ", ")
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    }
                    .width(140)
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
                    inspectorRow("Kind", device.kindLabel)
                    inspectorRow("Manufacturer", device.makeLabel)
                    if let model = device.model, !model.isEmpty {
                        inspectorRow("Model", model)
                    }
                    if let version = device.version, !version.isEmpty {
                        inspectorRow("Version", version)
                    }
                    if let role = device.deviceType, !role.isEmpty {
                        inspectorRow("Role", role)
                    }
                    if let serial = device.serialNumber, !serial.isEmpty {
                        inspectorRow("Serial", serial)
                    }
                    inspectorRow("Hostname", device.hostname ?? "—")
                    inspectorRow("MAC", device.mac ?? "—")
                    inspectorRow("Network", result.subnet)
                    inspectorRow("Gateway", device.isGateway ? String(localized: "Yes") : "—")
                    inspectorRow(
                        "Latency", ToolkitFormat.milliseconds(device.latencyMilliseconds))
                    if !device.serviceSummary.isEmpty {
                        Divider()
                        ToolkitSectionLabel(text: "Advertised services")
                        ToolkitChips(items: device.serviceSummary)
                    }
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
                                if let detail = serviceDetails[device.id]?[port] ?? device.banners[port] {
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
                "\(device.ip)\t\(device.mac ?? "-")\t\(device.hostname ?? "-")\t\(device.makeLabel)\t\(device.model ?? "-")\t\(device.versionLabel)\t\(device.kindLabel)\t\(device.serviceSummary.joined(separator: "|"))\t\(device.openPorts.map(String.init).joined(separator: ","))"
            )
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}
