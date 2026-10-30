import SwiftUI
import UniformTypeIdentifiers

struct OfflineCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    private let initialURL: URL?
    @State private var beacons: [CapturedBeacon] = []
    @State private var fileName = ""
    @State private var errorMessage: String?
    @State private var isParsing = false
    @State private var clients: [CapturedClient] = []
    @State private var showingClients = false
    @State private var showingMLO = false
    @State private var selectedBeaconId: String?
    @State private var searchText = ""
    @State private var currentURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
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
                Button("Close") { dismiss() }
            }
            .padding(14)
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
                .padding(30)
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
                        Text("· \(beacons.count) BSSIDs · \(clients.count) clients").font(.caption).foregroundColor(
                            .secondary)
                        Spacer()
                        TextField("Filter SSID/BSSID", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
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
                    .padding(10)
                    Table(filteredBeacons, selection: $selectedBeaconId) {
                        TableColumn("SSID", value: \.ssid)
                        TableColumn("BSSID", value: \.bssid)
                        TableColumn("Ch") { Text($0.channel.map(String.init) ?? "—") }.width(40)
                        TableColumn("RSSI") { Text($0.rssi.map { "\($0) dBm" } ?? "—") }.width(70)
                        TableColumn("Security", value: \.security)
                        TableColumn("IEs") { Text("\($0.informationElements.count)") }.width(40)
                        TableColumn("Clients") { Text($0.clientCount.map(String.init) ?? "—") }.width(55)
                        TableColumn("EHT") { Text($0.isEHT ? "Yes" : "—") }.width(40)
                    }
                    .tableStyle(.inset)
                    .frame(minHeight: 150, maxHeight: .infinity)

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
                                .padding(4)
                            }
                            .frame(height: 105)
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .frame(width: 840, height: 520)
        .task {
            if let initialURL { load(initialURL) }
        }
        .sheet(isPresented: $showingClients) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Clients").font(.headline)
                    Spacer()
                    Button("Close") { showingClients = false }
                }
                Table(clients) {
                    TableColumn("MAC", value: \.mac)
                    TableColumn("BSSID", value: \.bssid)
                    TableColumn("Frames") { Text("\($0.frameCount)") }.width(60)
                }
            }
            .padding(14)
            .frame(width: 560, height: 380)
        }
        .sheet(isPresented: $showingMLO) {
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
                                    .padding(4)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text("AP MLD \(group.apMLD)")
                                            .font(.caption.bold().monospaced())
                                        Text(group.ssid)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(
                                            "\(group.capturedLinkCount) of \(group.links.count) links captured"
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .padding(14)
            .frame(width: 640, height: 420)
        }
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
        Task {
            do {
                currentURL = url
                let data = try Data(contentsOf: url)
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.parse(data: data)
                }.value
                let parsedClients = try await Task.detached(priority: .userInitiated) {
                    try PcapAnalyzer.clients(data: data)
                }.value
                await MainActor.run {
                    isParsing = false
                    fileName = url.lastPathComponent
                    beacons = parsed
                    clients = parsedClients
                    if parsed.isEmpty { errorMessage = "No beacons or probe responses found." }
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
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-Capture.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
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
        var lines = ["ssid,bssid,channel,rssi,security,eht"]
        for item in beacons {
            let ssid = item.ssid.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append(
                "\"\(ssid)\",\(item.bssid),\(item.channel.map(String.init) ?? ""),"
                    + "\(item.rssi.map(String.init) ?? ""),\"\(item.security)\",\(item.isEHT)"
            )
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
