import AppKit
import SwiftUI

/// The device shelf: every device the LAN scanner has ever seen, with the
/// user's names, types, favourites, availability, risk findings and history.
struct DeviceShelfView: View {
    @ObservedObject var model: DeviceShelfViewModel
    @State private var aliasDraft = ""
    @State private var notesDraft = ""
    @State private var aliasSaveTask: Task<Void, Never>?
    @State private var serialDraft = ""
    @State private var locationDraft = ""
    @State private var showingClearConfirm = false
    @State private var showingQR = false
    @State private var wakeStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.devices.isEmpty {
                ToolkitCard {
                    ToolkitEmptyState(
                        icon: "square.stack.3d.up",
                        title: "The shelf fills itself",
                        message:
                            "Run a scan on the Scan tab. Every device that answers is kept here with its name, type, ports, availability and history — even when it is offline."
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    table
                    inspector
                        .frame(width: 290)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { syncDrafts() }
        .onChange(of: model.selectedID) { _ in syncDrafts() }
        .onChange(of: model.selectedDevice?.alias) { _ in syncDrafts() }
        .onDisappear {
            commitAlias()
            commitAssetFields()
        }
        .sheet(isPresented: $showingQR) {
            qrSheet
        }
        .confirmationDialog(
            String(localized: "Forget every device on the shelf?"),
            isPresented: $showingClearConfirm
        ) {
            Button("Remove all", role: .destructive) { model.clearAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Names, notes and history are deleted. The next scan starts a new shelf.")
        }
    }

    // MARK: - Header

    private var header: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(String(localized: "Search name, IP, vendor, MAC…"), text: $model.searchText)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 180, maxWidth: 260)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                    Picker("Filter", selection: $model.filter) {
                        ForEach(DeviceShelfViewModel.Filter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 350)

                    Spacer()

                    Menu {
                        Button(String(localized: "Export CSV…")) { export(.csv) }
                        Button(String(localized: "Export JSON…")) { export(.json) }
                        Button(String(localized: "QR labels (PDF)…")) { exportLabels() }
                        Divider()
                        Button(String(localized: "Copy as text")) { copyToPasteboard() }
                        Button(String(localized: "Forget all…"), role: .destructive) { showingClearConfirm = true }
                    } label: {
                        Label(String(localized: "Export"), systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack(spacing: 22) {
                    ToolkitMetric(title: "Devices", value: "\(model.devices.count)")
                    ToolkitMetric(title: "Online", value: "\(model.onlineCount)", tint: .green)
                    ToolkitMetric(
                        title: "Favourites", value: "\(model.favouriteCount)", tint: .yellow)
                    ToolkitMetric(
                        title: "With risks", value: "\(model.riskyDeviceCount)",
                        tint: model.riskyDeviceCount > 0 ? .orange : .primary)
                    ToolkitMetric(
                        title: "Warranty", value: "\(model.warrantyAttentionCount)",
                        tint: model.warrantyAttentionCount > 0 ? .orange : .primary)
                    Spacer()
                    if let merged = model.lastMergedAt {
                        Text(
                            String(
                                format: String(localized: "Shelf updated %@"),
                                merged.formatted(.relative(presentation: .named)))
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    } else if let subnet = model.lastScanSubnet {
                        Text(subnet)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Table

    private var table: some View {
        ToolkitCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    ToolkitSectionLabel(text: "Devices")
                    Spacer()
                    Text(String(format: String(localized: "%lld shown"), model.filteredDevices.count))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Table(model.filteredDevices, selection: $model.selectedID) {
                    TableColumn("") { device in
                        Button {
                            model.toggleFavourite(device.id)
                        } label: {
                            Image(systemName: device.isFavourite ? "star.fill" : "star")
                                .font(.caption2)
                                .foregroundColor(device.isFavourite ? .yellow : .secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help(
                            device.isFavourite
                                ? String(localized: "Remove from favourites") : String(localized: "Add to favourites"))
                    }
                    .width(22)

                    TableColumn("Device") { device in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(device.isOnline ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 6, height: 6)
                            Image(systemName: device.category.icon)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 14)
                            Text(device.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            if device.isNew {
                                Text("NEW")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                            }
                        }
                    }

                    TableColumn("Type") { device in
                        Text(device.category.title)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .width(90)

                    TableColumn("IP") { device in
                        Text(device.ip)
                            .font(.caption.monospaced())
                    }
                    .width(105)

                    TableColumn("Vendor") { device in
                        Text(device.vendor ?? "—")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .width(130)

                    TableColumn("Ports") { device in
                        Text(
                            device.openPorts.isEmpty
                                ? "—"
                                : device.openPorts.prefix(4).map(String.init).joined(separator: ",")
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                    .width(90)

                    TableColumn("RTT") { device in
                        Text(ToolkitFormat.milliseconds(device.latencyMs))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(70)

                    TableColumn(String(localized: "Availability")) { device in
                        Text(device.availabilityPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(80)

                    TableColumn(String(localized: "Warranty")) { device in
                        switch device.warranty {
                        case .unknown:
                            Text("—")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        case .active(let days):
                            Text("\(days) d")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        case .expiring(let days):
                            Text(days == 0 ? String(localized: "today") : "\(days) d")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.orange)
                        case .expired:
                            Text(String(localized: "expired"))
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .width(72)

                    TableColumn(String(localized: "Last seen")) { device in
                        Text(
                            device.isOnline
                                ? String(localized: "now")
                                : device.lastSeen.formatted(.relative(presentation: .named))
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .width(95)
                }
                .frame(minHeight: 240, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 9) {
                if let device = model.selectedDevice {
                    HStack(spacing: 8) {
                        Image(systemName: device.category.icon)
                            .font(.title3)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.displayName)
                                .font(.headline)
                                .lineLimit(2)
                            Text(device.ip)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            model.toggleFavourite(device.id)
                        } label: {
                            Image(systemName: device.isFavourite ? "star.fill" : "star")
                                .foregroundColor(device.isFavourite ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        ToolkitStatusPill(
                            text: device.isOnline
                                ? String(localized: "Online") : String(localized: "Offline"),
                            tone: device.isOnline ? .good : .neutral)
                        if let availability = device.availabilityPercent {
                            ToolkitStatusPill(
                                text: String(
                                    format: String(localized: "%.0f%% available"), availability),
                                tone: availability >= 90 ? .good : (availability >= 50 ? .warning : .bad))
                        }
                    }

                    Divider()

                    TextField(
                        String(localized: "Name"),
                        text: Binding(
                            get: { aliasDraft },
                            set: { aliasDraft = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { commitAlias() }
                    .onChange(of: aliasDraft) { _ in scheduleAliasSave() }
                    .help(
                        String(
                            localized:
                                "Your name for this device; it survives rescans and DHCP changes"))

                    Picker(
                        "Type",
                        selection: Binding(
                            get: { model.device(id: device.id)?.category ?? device.category },
                            set: { model.setCategory($0, for: device.id) }
                        )
                    ) {
                        ForEach(DeviceCategory.allCases) { category in
                            Label(category.title, systemImage: category.icon).tag(category)
                        }
                    }
                    .font(.caption)

                    inspectorRow("Manufacturer", device.makeLabel)
                    if let model = device.model, !model.isEmpty {
                        inspectorRow("Model", model)
                    }
                    if let version = device.version, !version.isEmpty {
                        inspectorRow("Version", version)
                    }
                    if let role = device.role, !role.isEmpty {
                        inspectorRow("Role", role)
                    }
                    inspectorRow("Hostname", device.hostname ?? "—")
                    inspectorRow("MAC", device.mac ?? "—")
                    inspectorRow("Source", model.lastScanSubnet ?? "—")
                    inspectorRow(
                        "First seen",
                        device.firstSeen.formatted(date: .abbreviated, time: .shortened))
                    inspectorRow(
                        "Last seen",
                        device.lastSeen.formatted(date: .abbreviated, time: .shortened))

                    Divider()
                    HStack {
                        ToolkitSectionLabel(text: "Asset")
                        Spacer()
                        if device.warranty.needsAttention {
                            ToolkitStatusPill(text: device.warranty.title, tone: .warning)
                        }
                    }
                    inspectorRow("Asset tag", device.assetTag ?? "—")
                    assetField("Serial number", text: $serialDraft)
                    assetField("Location", text: $locationDraft)
                    HStack(spacing: 6) {
                        Text("Purchased").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { device.purchaseDate ?? Date() },
                                set: { model.setPurchaseDate($0, for: device.id) }),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .controlSize(.mini)
                        if device.purchaseDate != nil {
                            Button("Clear") { model.setPurchaseDate(nil, for: device.id) }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Warranty ends").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { device.warrantyEnd ?? Date() },
                                set: { model.setWarrantyEnd($0, for: device.id) }),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .controlSize(.mini)
                        if device.warrantyEnd != nil {
                            Button("Clear") { model.setWarrantyEnd(nil, for: device.id) }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                        }
                    }
                    if device.warranty.isKnown {
                        Text(device.warranty.title)
                            .font(.caption2)
                            .foregroundColor(device.warranty.needsAttention ? .orange : .secondary)
                    }
                    HStack(spacing: 8) {
                        Button {
                            showingQR = true
                        } label: {
                            Label("QR label", systemImage: "qrcode")
                        }
                        .controlSize(.small)
                        if let mac = device.mac {
                            Button {
                                wake(device, mac: mac)
                            } label: {
                                Label("Wake", systemImage: "power")
                            }
                            .controlSize(.small)
                            .help(String(localized: "Send a Wake-on-LAN magic packet to \(mac)"))
                        }
                    }
                    if let wakeStatus {
                        Text(wakeStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if !device.serviceLabels.isEmpty {
                        ToolkitSectionLabel(text: "Advertised services")
                        ToolkitChips(items: device.serviceLabels)
                    }

                    if device.latencySamples.count > 1 {
                        ToolkitSectionLabel(text: "Latency")
                        LatencySparkline(samples: device.latencySamples)
                            .frame(height: 34)
                    }

                    let risks = DeviceRiskCatalog.findings(for: device.openPorts)
                    Divider()
                    HStack {
                        ToolkitSectionLabel(text: "Risks")
                        Spacer()
                        Text(
                            String(
                                format: String(localized: "score %lld"),
                                DeviceRiskCatalog.score(for: risks))
                        )
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(
                            DeviceRiskCatalog.score(for: risks) >= 80
                                ? .green : (risks.isEmpty ? .secondary : .orange))
                    }
                    if risks.isEmpty {
                        Text("No risky ports detected on the probed set.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(risks) { risk in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(color(for: risk.severity))
                                        .frame(width: 6, height: 6)
                                    Text("\(risk.port)/tcp · \(risk.title)")
                                        .font(.caption2.weight(.medium))
                                    Spacer()
                                    Text(risk.severity.title)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(color(for: risk.severity))
                                }
                                Text(risk.advice)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Divider()
                    ToolkitSectionLabel(text: "Open ports")
                    if device.openPorts.isEmpty {
                        Text("None of the probed ports answered.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        portsFlow(device.openPorts)
                    }

                    Divider()
                    ToolkitSectionLabel(text: "Notes")
                    TextEditor(text: $notesDraft)
                        .font(.caption)
                        .frame(minHeight: 44, maxHeight: 64)
                        .scrollContentBackground(.hidden)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        .onChange(of: notesDraft) { value in
                            model.setNotes(value, for: device.id)
                        }

                    if !device.events.isEmpty {
                        Divider()
                        ToolkitSectionLabel(text: "History")
                        ForEach(device.events.suffix(5).reversed()) { event in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: icon(for: event.kind))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(width: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.detail)
                                        .font(.caption2)
                                    Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    Divider()
                    Button(String(localized: "Forget this device"), role: .destructive) {
                        model.forget(device.id)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                } else {
                    Text("Select a device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func portsFlow(_ ports: [UInt16]) -> some View {
        // Simple wrapping rows of port chips, four per line.
        let rows = stride(from: 0, to: ports.count, by: 4).map {
            Array(ports[$0..<min($0 + 4, ports.count)])
        }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { port in
                        Text("\(port)")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
    }

    private func inspectorRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.monospaced())
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func color(for severity: DeviceRiskFinding.Severity) -> Color {
        switch severity {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .info: return .secondary
        }
    }

    private func icon(for kind: DeviceShelfEvent.Kind) -> String {
        switch kind {
        case .joined: return "plus.circle"
        case .returned: return "arrow.uturn.left.circle"
        case .left: return "minus.circle"
        case .portsChanged: return "bolt.circle"
        }
    }

    private func syncDrafts() {
        aliasSaveTask?.cancel()
        aliasDraft = model.selectedDevice?.alias ?? ""
        notesDraft = model.selectedDevice?.notes ?? ""
        serialDraft = model.selectedDevice?.serialNumber ?? ""
        locationDraft = model.selectedDevice?.location ?? ""
        wakeStatus = nil
    }

    // MARK: - Asset register

    private func assetField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Spacer()
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .frame(width: 150)
                .onSubmit { commitAssetFields() }
                .onChange(of: text.wrappedValue) { _ in commitAssetFields() }
        }
    }

    private func commitAssetFields() {
        guard let id = model.selectedID else { return }
        model.setSerial(serialDraft, for: id)
        model.setLocation(locationDraft, for: id)
    }

    private func wake(_ device: ShelfDevice, mac: String) {
        do {
            try WakeOnLAN.send(mac: mac)
            wakeStatus = String(format: String(localized: "Magic packet sent to %@"), mac)
        } catch {
            wakeStatus = error.localizedDescription
        }
    }

    private var qrSheet: some View {
        VStack(spacing: 12) {
            if let device = model.selectedDevice, let tag = device.assetTag,
                let image = QRCode.image(for: DeviceShelfAsset.deepLink(for: tag), scale: 12)
            {
                Text(device.displayName).font(.headline)
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                Text(DeviceShelfAsset.deepLink(for: tag))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                Text(
                    "The code holds the asset tag, not the MAC address. Any Mac with LanFi opens this device from the shelf."
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 260)
                HStack {
                    Button("Copy link") { copyLabelLink(tag) }
                    Button("Save PNG…") { saveLabelPNG(tag) }
                    Button("Close") { showingQR = false }
                }
            } else {
                Text("Select a device with an asset tag.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Close") { showingQR = false }
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func copyLabelLink(_ tag: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DeviceShelfAsset.deepLink(for: tag), forType: .string)
    }

    private func saveLabelPNG(_ tag: String) {
        guard let data = DeviceLabelPDF.png(for: tag) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(tag).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func exportLabels() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "lanfi-device-labels.pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? DeviceLabelPDF.data(for: model.devices).write(to: url, options: .atomic)
    }

    /// Typing an alias writes the shelf JSON, so debounce it instead of
    /// rewriting the file on every keystroke.
    private func scheduleAliasSave() {
        guard let id = model.selectedID else { return }
        let value = aliasDraft
        aliasSaveTask?.cancel()
        aliasSaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            model.setAlias(value, for: id)
        }
    }

    private func commitAlias() {
        aliasSaveTask?.cancel()
        aliasSaveTask = nil
        guard let id = model.selectedID else { return }
        model.setAlias(aliasDraft, for: id)
    }

    // MARK: - Export

    private enum ExportKind {
        case csv, json
    }

    private func export(_ kind: ExportKind) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = kind == .csv ? "lanfi-devices.csv" : "lanfi-devices.json"
        panel.allowedContentTypes = kind == .csv ? [.commaSeparatedText] : [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = kind == .csv ? model.csv : model.json
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.csv, forType: .string)
    }
}

/// Tiny RTT trend for the shelf inspector.
struct LatencySparkline: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(samples.max() ?? 1, 1)
            let minValue = samples.min() ?? 0
            let span = max(maxValue - minValue, 0.1)
            Path { path in
                for (index, sample) in samples.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(samples.count - 1, 1))
                    let ratio = (sample - minValue) / span
                    let y = geo.size.height - CGFloat(ratio) * geo.size.height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
    }
}
