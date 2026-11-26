import PostHog
import SwiftUI
import UniformTypeIdentifiers

struct OfflineCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    private let initialURL: URL?
    private let embedded: Bool
    private let monitor: MonitorViewModel?
    @State private var beacons: [CapturedBeacon] = []
    @State private var fileName = ""
    @State private var errorMessage: String?
    @State private var isParsing = false
    @State private var clients: [CapturedClient] = []
    @State private var security: CaptureSecurityReport = .empty
    @State private var shelfDevices: [String: ShelfDevice] = [:]
    @State private var showingClients = false
    @State private var showingSecurity = false
    @State private var showingMLO = false
    @State private var clientsOnlySelectedNetwork = false
    @State private var selectedBeaconId: String?
    @State private var searchText = ""
    @State private var currentURL: URL?

    init(
        initialURL: URL? = nil, embedded: Bool = false,
        monitor: MonitorViewModel? = nil
    ) {
        self.initialURL = initialURL
        self.embedded = embedded
        self.monitor = monitor
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
                if !embedded {
                    Button("Close") { dismiss() }
                }
            }
            .padding(DesignToken.Spacing.card)
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
                .padding(DesignToken.Spacing.emptyState)
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
                        Text("· \(beacons.count) BSSIDs · \(clients.count) clients\(securitySummary)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("Filter SSID/BSSID", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                        Button {
                            showingSecurity = true
                        } label: {
                            Label(
                                "Security…",
                                systemImage: security.criticalCount > 0
                                    ? "exclamationmark.shield.fill" : "shield")
                        }
                        .controlSize(.small)
                        .help("EAPOL handshakes, PMKIDs and management-frame disruption")
                        Button("Open in Wireshark…") { openInWireshark() }
                            .controlSize(.small)
                        Button("Clients…") { showingClients = true }
                            .controlSize(.small)
                            .disabled(clients.isEmpty)
                        Button("MLO…") { showingMLO = true }
                            .controlSize(.small)
                            .disabled(mloGroups.isEmpty)
                        Menu {
                            Button("CSV…") { exportCSV() }
                            Button("JSON…") { exportJSON() }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(DesignToken.Spacing.compact)
                    AppTable(
                        columns: [
                            AppTableColumn(
                                id: "ssid", title: "SSID", minWidth: 130,
                                value: { .text($0.ssid) }
                            ) { Text($0.ssid) },
                            AppTableColumn(
                                id: "bssid", title: "BSSID", minWidth: 140,
                                value: { .text($0.bssid) }
                            ) { Text($0.bssid).font(.caption.monospaced()) },
                            AppTableColumn(
                                id: "channel", title: "Ch", minWidth: AppColumnWidth.index,
                                value: { .number($0.channel) }
                            ) { Text($0.channel.map(String.init) ?? "—") },
                            AppTableColumn(
                                id: "rssi", title: "RSSI", minWidth: 70,
                                value: { .number($0.rssi) }
                            ) { Text($0.rssi.map { "\($0) dBm" } ?? "—") },
                            AppTableColumn(
                                id: "security", title: "Security", minWidth: 120,
                                value: { .text($0.security) }
                            ) { Text($0.security) },
                            AppTableColumn(
                                id: "handshake", title: "Handshake", minWidth: AppColumnWidth.compact,
                                value: { .text(handshakeStatus(for: $0).text) }
                            ) { beacon in
                                let status = handshakeStatus(for: beacon)
                                Text(status.text)
                                    .foregroundColor(status.color)
                                    .help(status.help)
                            },
                            AppTableColumn(
                                id: "deauth", title: "Deauth", minWidth: AppColumnWidth.small,
                                value: { .number(security.counters(for: $0.bssid)?.disruptionCount) }
                            ) { beacon in
                                let count = security.counters(for: beacon.bssid)?.disruptionCount ?? 0
                                Text(count == 0 ? "—" : "\(count)")
                                    .foregroundColor(
                                        count >= CaptureSecurityAnalyzer.burstThreshold ? .red : .secondary)
                            },
                            AppTableColumn(
                                id: "ies", title: "IEs", minWidth: AppColumnWidth.index,
                                value: { .number($0.informationElements.count) }
                            ) { Text("\($0.informationElements.count)") },
                            AppTableColumn(
                                id: "clients", title: "Clients", minWidth: AppColumnWidth.small,
                                value: { .number($0.clientCount) }
                            ) { Text($0.clientCount.map(String.init) ?? "—") },
                            AppTableColumn(
                                id: "eht", title: "EHT", minWidth: AppColumnWidth.index,
                                value: { .flag($0.isEHT) }
                            ) { Text($0.isEHT ? "Yes" : "—") },
                        ],
                        rows: filteredBeacons, initialKey: "rssi", ascending: false,
                        selection: $selectedBeaconId
                    )
                    .frame(minHeight: 150, maxHeight: .infinity)
                    .padding(.horizontal, DesignToken.Spacing.tight)
                    .padding(.top, DesignToken.Spacing.tight)

                    if let selectedBeacon {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Information elements · \(selectedBeacon.informationElements.count)")
                                    .font(.caption.bold())
                                Spacer()
                                Button("Copy IEs") { copyIEs(selectedBeacon) }
                                    .controlSize(.mini)
                            }
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 3) {
                                    ForEach(selectedBeacon.informationElements) { element in
                                        HStack(alignment: .top, spacing: 6) {
                                            Text("\(element.elementId)")
                                                .font(.caption2.monospaced())
                                                .foregroundColor(.secondary)
                                                .frame(width: 26, alignment: .trailing)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(element.name).font(.caption2.bold())
                                                Text(element.summary)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                                .padding(DesignToken.Spacing.tight)
                            }
                            .frame(height: 105)
                        }
                        .padding(.horizontal, DesignToken.Spacing.compact)
                        .padding(.bottom, DesignToken.Spacing.small)
                    }
                }
            }
        }
        .frame(width: 940, height: 560)
        .task {
            shelfDevices = Dictionary(
                DeviceShelfStore().load().compactMap { device in
                    device.mac.map { ($0.uppercased(), device) }
                }, uniquingKeysWith: { first, _ in first })
            if let initialURL { load(initialURL) }
        }
        .sheet(isPresented: $showingClients) {
            clientsSheet
        }
        .sheet(isPresented: $showingSecurity) {
            securitySheet
        }
        .sheet(isPresented: $showingMLO) {
            mloSheet
        }
    }

    // MARK: - Clients

    private var clientsSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clients").font(.headline)
                Text("\(filteredClients.count) of \(clients.count)").font(.caption).foregroundColor(.secondary)
                Spacer()
                Toggle("Only \(selectedBeacon?.ssid ?? "selected network")", isOn: $clientsOnlySelectedNetwork)
                    .toggleStyle(.checkbox)
                    .disabled(selectedBeacon == nil)
                Button("Close") { showingClients = false }
            }
            AppTable(
                columns: [
                    AppTableColumn(
                        id: "mac", title: "MAC", minWidth: 120,
                        value: { .text($0.mac) }
                    ) { Text($0.mac).font(.caption.monospaced()) },
                    AppTableColumn(
                        id: "vendor", title: "Vendor", minWidth: AppColumnWidth.wide,
                        value: { .text(OUIParser.vendor(for: $0.mac)) }
                    ) { Text(OUIParser.vendor(for: $0.mac)).lineLimit(1) },
                    AppTableColumn(
                        id: "bssid", title: "BSSID", minWidth: 140,
                        value: { .text($0.bssid) }
                    ) { Text($0.bssid).font(.caption.monospaced()) },
                    AppTableColumn(
                        id: "frames", title: "Frames", minWidth: AppColumnWidth.small,
                        value: { .number($0.frameCount) }
                    ) { Text("\($0.frameCount)").monospacedDigit() },
                    AppTableColumn(
                        id: "management", title: "Mgmt/Data", minWidth: 80,
                        value: { .number($0.managementFrames) }
                    ) { Text("\($0.managementFrames)/\($0.dataFrames)").monospacedDigit() },
                    AppTableColumn(
                        id: "rssi", title: "RSSI", minWidth: AppColumnWidth.short,
                        value: { .number($0.rssi) }
                    ) { Text($0.rssi.map { "\($0) dBm" } ?? "—") },
                    AppTableColumn(
                        id: "lastSeen", title: "Last seen", minWidth: 80,
                        value: { .number($0.lastSeen.timeIntervalSinceReferenceDate) }
                    ) { Text(Self.timeLabel($0.lastSeen)) },
                    AppTableColumn(
                        id: "probes", title: "Probes", minWidth: AppColumnWidth.wide,
                        value: { .text($0.probeSSIDs.joined(separator: ", ")) }
                    ) { client in
                        Text(client.probeSSIDs.isEmpty ? "—" : client.probeSSIDs.joined(separator: ", "))
                            .lineLimit(1)
                            .help(client.probeSSIDs.joined(separator: "\n"))
                    },
                    AppTableColumn(
                        id: "shelf", title: "Device Shelf", minWidth: AppColumnWidth.long,
                        value: { .text(shelfDevices[$0.mac.uppercased()]?.displayName) }
                    ) { client in
                        let device = shelfDevices[client.mac.uppercased()]
                        Text(device.map { "\($0.displayName) · \($0.ip)" } ?? "—")
                            .lineLimit(1)
                            .foregroundColor(device == nil ? .secondary : .primary)
                    },
                ],
                rows: filteredClients, initialKey: "frames", ascending: false
            )
        }
        .padding(DesignToken.Spacing.card)
        .frame(width: 940, height: 440)
    }

    private var filteredClients: [CapturedClient] {
        guard clientsOnlySelectedNetwork, let bssid = selectedBeacon?.bssid else { return clients }
        return clients.filter { $0.bssid.caseInsensitiveCompare(bssid) == .orderedSame }
    }

    // MARK: - Security

    private var securitySheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Capture security").font(.headline)
                Text(
                    "\(security.completeHandshakeCount) handshakes · \(security.pmkidCount) PMKID · \(security.deauthTotal) deauth · \(security.disassocTotal) disassoc"
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Button("Close") { showingSecurity = false }
            }

            if security.findings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "shield.checkerboard")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No EAPOL or management anomalies in this capture.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(security.findings) { finding in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: finding.severity.symbol)
                                    .foregroundColor(color(for: finding.severity))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(finding.title).font(.caption.bold())
                                        if let bssid = finding.bssid {
                                            Text(bssid)
                                                .font(.caption2.monospaced())
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(finding.severity.title)
                                            .font(.caption2)
                                            .foregroundColor(color(for: finding.severity))
                                    }
                                    Text(finding.detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(DesignToken.Spacing.small)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(DesignToken.Radius.control)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            HStack {
                Text("Management frames").font(.caption.bold())
                Spacer()
            }
            if security.management.isEmpty {
                Text("No beacons, deauth or disassociation frames counted.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                AppTable(
                    columns: [
                        AppTableColumn(
                            id: "bssid", title: "BSSID", minWidth: 140,
                            value: { .text($0.bssid) }
                        ) { Text($0.bssid).font(.caption.monospaced()) },
                        AppTableColumn(
                            id: "beacons", title: "Beacons", minWidth: AppColumnWidth.short,
                            value: { .number($0.beacons) }
                        ) { Text("\($0.beacons)").monospacedDigit() },
                        AppTableColumn(
                            id: "probeResponses", title: "Probe resp.", minWidth: 80,
                            value: { .number($0.probeResponses) }
                        ) { Text("\($0.probeResponses)").monospacedDigit() },
                        AppTableColumn(
                            id: "deauth", title: "Deauth", minWidth: 60,
                            value: { .number($0.deauth) }
                        ) { Text("\($0.deauth)").monospacedDigit() },
                        AppTableColumn(
                            id: "disassoc", title: "Disassoc", minWidth: 70,
                            value: { .number($0.disassoc) }
                        ) { Text("\($0.disassoc)").monospacedDigit() },
                        AppTableColumn(
                            id: "burst", title: "Burst", minWidth: AppColumnWidth.tiny,
                            value: { .flag($0.burst) }
                        ) { Text($0.burst ? "Yes" : "—").foregroundColor($0.burst ? .red : .secondary) },
                        AppTableColumn(
                            id: "reasons", title: "Reasons", minWidth: 160,
                            value: { .number($0.reasons.map(\.count).reduce(0, +)) }
                        ) { counters in
                            let text = counters.reasons.map { "\($0.label) ×\($0.count)" }.joined(separator: ", ")
                            Text(text.isEmpty ? "—" : text).lineLimit(1).help(text)
                        },
                    ],
                    rows: security.management, initialKey: "bssid"
                )
            }
        }
        .padding(DesignToken.Spacing.card)
        .frame(width: 760, height: 520)
    }

    private func color(for severity: CaptureFinding.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private var securitySummary: String {
        var parts: [String] = []
        if security.completeHandshakeCount > 0 {
            parts.append("\(security.completeHandshakeCount) handshakes")
        }
        if security.pmkidCount > 0 {
            parts.append("\(security.pmkidCount) PMKID")
        }
        if security.deauthTotal + security.disassocTotal > 0 {
            parts.append("\(security.deauthTotal) deauth")
        }
        guard !parts.isEmpty else { return "" }
        return " · " + parts.joined(separator: " · ")
    }

    private func handshakeStatus(for beacon: CapturedBeacon) -> (text: String, color: Color, help: String) {
        guard let handshake = security.handshake(for: beacon.bssid) else {
            return ("—", .secondary, "No EAPOL-Key frames for this BSSID")
        }
        if handshake.hasPMKID {
            return (
                "PMKID", .red,
                "PMKID captured in message 1 — offline dictionary attack possible without a client"
            )
        }
        if handshake.hasCompleteHandshake {
            return (
                "4-way", .orange,
                "4-way handshake messages \(handshake.messageLabel) captured — offline dictionary attack possible"
            )
        }
        return (
            "partial \(handshake.messageLabel)", .secondary,
            "\(handshake.keyFrameCount) EAPOL-Key frames, not enough for an offline attack"
        )
    }

    // MARK: - MLO

    private var mloSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MLO groups").font(.headline)
                Spacer()
                Button("Close") { showingMLO = false }
            }
            if mloGroups.isEmpty {
                Text("No Multi-Link elements found in this capture.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(mloGroups) { group in
                            GroupBox {
                                VStack(spacing: 0) {
                                    ForEach(group.links) { link in
                                        HStack(spacing: 8) {
                                            Text(link.linkID.map { "Link \($0)" } ?? "Link ?")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 50, alignment: .leading)
                                            Text(link.bssid ?? "—")
                                                .font(.caption2.monospaced())
                                            Spacer()
                                            Text(link.channel.map { "ch \($0)" } ?? "—")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 46, alignment: .trailing)
                                            Text(link.rssi.map { "\($0) dBm" } ?? "—")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 64, alignment: .trailing)
                                            Text(link.seenInCapture ? "Captured" : "Not in capture")
                                                .font(.caption2)
                                                .foregroundColor(link.seenInCapture ? .green : .orange)
                                                .frame(width: 86, alignment: .trailing)
                                        }
                                        .padding(.vertical, 3)
                                        if link.id != group.links.last?.id { Divider() }
                                    }
                                }
                                .padding(DesignToken.Spacing.tight)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("AP MLD \(group.apMLD)")
                                        .font(.caption.bold().monospaced())
                                    Text(group.ssid)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(group.capturedLinkCount) of \(group.links.count) links captured")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(DesignToken.Spacing.tight)
                }
            }
        }
        .padding(DesignToken.Spacing.card)
        .frame(width: 640, height: 420)
    }

    private var mloGroups: [MLOGroup] {
        MLOGroupAssembler.assemble(beacons: beacons)
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
        clients = []
        security = .empty
        Task {
            do {
                currentURL = url
                let data = try PcapAnalyzer.mappedData(at: url)
                let summary = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.summary(data: data)
                }.value
                await MainActor.run {
                    isParsing = false
                    fileName = url.lastPathComponent
                    beacons = summary.beacons
                    clients = summary.clients
                    security = summary.security
                    monitor?.ingestCapture(summary.security)
                    PostHogSDK.shared.capture(
                        "packet_capture_loaded",
                        properties: [
                            "beacon_count": summary.beacons.count,
                            "client_count": summary.clients.count,
                            "has_security_findings": !summary.security.findings.isEmpty,
                        ])
                    if summary.beacons.isEmpty { errorMessage = "No beacons or probe responses found." }
                }
            } catch {
                await MainActor.run {
                    isParsing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var filteredBeacons: [CapturedBeacon] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return beacons }
        return beacons.filter {
            $0.ssid.localizedCaseInsensitiveContains(term)
                || $0.bssid.localizedCaseInsensitiveContains(term)
        }
    }

    private var selectedBeacon: CapturedBeacon? {
        beacons.first { $0.id == selectedBeaconId }
    }

    private func openInWireshark() {
        guard let url = currentURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func exportJSON() {
        let payload: [String: Any] = [
            "generator": "LanFi",
            "bssids": beacons.count,
            "clients": clients.count,
            "networks": beacons.map { beacon in
                [
                    "ssid": beacon.ssid, "bssid": beacon.bssid,
                    "channel": beacon.channel as Any, "rssi": beacon.rssi as Any,
                    "security": beacon.security, "isEHT": beacon.isEHT,
                    "ieCount": beacon.informationElements.count,
                    "clientCount": beacon.clientCount as Any,
                ]
            },
            "mloGroups": mloGroups.map { group in
                [
                    "apMLD": group.apMLD,
                    "ssid": group.ssid,
                    "links": group.links.map { link in
                        [
                            "linkID": link.linkID as Any,
                            "bssid": link.bssid as Any,
                            "channel": link.channel as Any,
                            "rssi": link.rssi as Any,
                            "seenInCapture": link.seenInCapture,
                        ]
                    },
                ]
            },
            "security": [
                "handshakes": security.handshakes.map { handshake in
                    [
                        "bssid": handshake.bssid,
                        "keyFrames": handshake.keyFrameCount,
                        "messages": handshake.messageLabel,
                        "complete": handshake.hasCompleteHandshake,
                        "pmkid": handshake.hasPMKID,
                    ]
                },
                "management": security.management.map { counters in
                    [
                        "bssid": counters.bssid,
                        "beacons": counters.beacons,
                        "probeResponses": counters.probeResponses,
                        "deauth": counters.deauth,
                        "disassoc": counters.disassoc,
                        "burst": counters.burst,
                        "reasons": counters.reasons.map { ["code": $0.code, "count": $0.count] },
                    ]
                },
                "findings": security.findings.map { finding in
                    [
                        "id": finding.id,
                        "severity": finding.severity.title,
                        "title": finding.title,
                        "detail": finding.detail,
                        "bssid": finding.bssid as Any,
                    ]
                },
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-Capture.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            captureExport(format: "json")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyIEs(_ beacon: CapturedBeacon) {
        let text = beacon.informationElements.map { element in
            "\(element.name) (\(element.elementId)): \(element.summary)\n\(element.detailLines.joined(separator: "\n"))"
        }.joined(separator: "\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-Capture.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var lines = ["ssid,bssid,channel,rssi,security,eht,handshake,pmkid,deauth,disassoc"]
        for item in beacons {
            let ssid = item.ssid.replacingOccurrences(of: "\"", with: "\"\"")
            let handshake = security.handshake(for: item.bssid)
            let counters = security.counters(for: item.bssid)
            lines.append(
                "\"\(ssid)\",\(item.bssid),\(item.channel.map(String.init) ?? ""),"
                    + "\(item.rssi.map(String.init) ?? ""),\"\(item.security)\",\(item.isEHT),"
                    + "\(handshake?.hasCompleteHandshake == true),"
                    + "\(handshake?.hasPMKID == true),"
                    + "\(counters?.deauth ?? 0),\(counters?.disassoc ?? 0)"
            )
        }
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            captureExport(format: "csv")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func captureExport(format: String) {
        PostHogSDK.shared.capture(
            "packet_capture_exported",
            properties: [
                "export_format": format,
                "beacon_count": beacons.count,
                "client_count": clients.count,
            ])
    }

    private static func timeLabel(_ date: Date) -> String {
        guard date != .distantPast else { return "—" }
        return date.formatted(date: .omitted, time: .standard)
    }
}
