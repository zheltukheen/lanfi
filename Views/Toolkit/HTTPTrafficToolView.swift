import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Reads a HAR archive produced elsewhere (browser DevTools, Proxyman,
/// Charles, Rockxy) and turns it into insights: slowest requests, failures,
/// bytes per host, timing phases and a shareable report. LanFi never proxies
/// or decrypts traffic itself.
struct HTTPTrafficToolView: View {
    @ObservedObject var model: HTTPTrafficToolModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                if let error = model.errorMessage {
                    ToolkitErrorBanner(message: error)
                }
                if let traffic = model.traffic, let insights = model.insights {
                    metrics(insights)
                    if traffic.entries.isEmpty {
                        ToolkitEmptyState(
                            icon: "tray",
                            title: "Nothing captured",
                            message: "This HAR archive has no requests."
                        )
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            requestTable
                            inspectorColumn
                        }
                        hostBreakdown(insights)
                    }
                } else if !model.isLoading {
                    ToolkitEmptyState(
                        icon: "list.bullet.rectangle.portrait",
                        title: "Analyze HTTP traffic",
                        message:
                            "Export a HAR file from Safari or Chrome DevTools, Proxyman, Charles or Rockxy, then open it here. LanFi analyzes the recording; it does not proxy or decrypt traffic itself."
                    )
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading the HAR archive…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(18)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Open HAR…") { open() }
                        .buttonStyle(.borderedProminent)
                    if !model.fileName.isEmpty {
                        Text(model.fileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Markdown Report…") { exportMarkdown() }
                        .disabled(model.traffic == nil)
                    Button("CSV…") { exportCSV() }
                        .disabled(model.traffic == nil)
                    Button("Clear") { model.clear() }
                        .buttonStyle(.borderless)
                        .disabled(model.traffic == nil)
                }
                HStack(spacing: 10) {
                    TextField("Filter URL, method or MIME type", text: $model.search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Picker("Status", selection: $model.statusFilter) {
                        ForEach(HARStatusFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    Picker("Host", selection: $model.hostFilter) {
                        Text("All hosts").tag("")
                        ForEach(model.hosts, id: \.self) { host in
                            Text(host).tag(host)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    Spacer()
                    Toggle("Redact credentials", isOn: $model.redactExports)
                        .toggleStyle(.checkbox)
                        .help(
                            "Masks Authorization, cookie and token values in exports, the inspector and copied cURL commands. The loaded capture is unchanged."
                        )
                }
            }
        }
    }

    // MARK: - Metrics

    private func metrics(_ insights: HARInsights) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 14) {
                ToolkitMetric(title: "Requests", value: "\(insights.requestCount)")
                ToolkitMetric(
                    title: "Failures", value: "\(insights.failureCount)",
                    tint: insights.failureCount > 0 ? .red : .primary)
                ToolkitMetric(
                    title: "Transferred", value: HARTrafficAnalyzer.bytes(insights.transferBytes))
                ToolkitMetric(
                    title: "Average", value: HAREntry.milliseconds(insights.averageMilliseconds))
                ToolkitMetric(title: "p95", value: HAREntry.milliseconds(insights.p95Milliseconds))
                ToolkitMetric(title: "Cached", value: "\(insights.cachedCount)")
                ToolkitMetric(
                    title: "Slowest phase",
                    value: insights.slowestPhase.map {
                        "\($0.name) · \(HAREntry.milliseconds($0.milliseconds))"
                    } ?? "—"
                )
            }
        }
    }

    // MARK: - Requests

    private var requestTable: some View {
        ToolkitCard(padding: 0) {
            Table(model.entries, selection: $model.selectedEntryID) {
                TableColumn("Status") { entry in
                    Text(entry.statusLabel)
                        .font(.caption.monospaced())
                        .foregroundColor(statusColor(entry))
                        .frame(width: 44, alignment: .leading)
                }
                .width(56)
                TableColumn("Method") { entry in
                    Text(entry.request.method)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .width(64)
                TableColumn("Host", value: \.host)
                TableColumn("Path") { entry in
                    Text(entry.path).lineLimit(1).help(entry.request.url)
                }
                TableColumn("Type") { entry in
                    Text(entry.response.mimeType).lineLimit(1)
                }
                .width(130)
                TableColumn("Size") { entry in
                    Text(HARTrafficAnalyzer.bytes(entry.sizeBytes))
                }
                .width(70)
                TableColumn("Time") { entry in
                    Text(entry.durationLabel)
                }
                .width(70)
            }
            .tableStyle(.inset)
            .frame(minWidth: 520, minHeight: 320)
        }
    }

    private var inspectorColumn: some View {
        Group {
            if let entry = model.selectedEntry {
                inspector(entry)
            } else {
                ToolkitCard {
                    VStack(spacing: 8) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("Select a request")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .frame(width: 380)
    }

    private func inspector(_ entry: HAREntry) -> some View {
        ToolkitCard {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(entry.request.method) \(entry.statusLabel)")
                            .font(.headline)
                            .foregroundColor(statusColor(entry))
                        Spacer()
                        Button("Copy cURL") { copyCurl(entry) }
                            .controlSize(.small)
                    }
                    Text(entry.request.url)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Text(
                        "\(HARTrafficAnalyzer.bytes(entry.sizeBytes)) transferred · "
                            + "\(HARTrafficAnalyzer.bytes(entry.response.content.size)) uncompressed"
                            + (entry.isFromCache ? " · from cache" : "")
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    if let server = entry.serverIP, !server.isEmpty {
                        Text(serverLine(server, connection: entry.connection))
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }

                    Divider()
                    ToolkitSectionLabel(text: "Timings")
                    if entry.timings.phases.isEmpty {
                        Text("No phase timings in this entry.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        let maxMilliseconds = entry.timings.phases.map(\.milliseconds).max() ?? 1
                        ForEach(Array(entry.timings.phases.enumerated()), id: \.offset) { item in
                            timingRow(item.element, maxMilliseconds: maxMilliseconds)
                        }
                    }

                    if !entry.request.query.isEmpty {
                        Divider()
                        ToolkitSectionLabel(text: "Query")
                        let query =
                            model.redactExports
                            ? HARRedaction.query(entry.request.query) : entry.request.query
                        ForEach(query, id: \.self) { item in
                            Text("\(item.name) = \(item.value)")
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    Divider()
                    ToolkitSectionLabel(text: "Request headers")
                    headerList(model.headers(for: entry.request.headers))
                    if let body = entry.request.postData?.text, !body.isEmpty {
                        ToolkitSectionLabel(text: "Request body")
                        Text(model.redactExports ? HARRedaction.body(body) : body)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(6)
                    }

                    Divider()
                    ToolkitSectionLabel(text: "Response headers")
                    headerList(model.headers(for: entry.response.headers))
                }
            }
            .frame(maxHeight: 420)
        }
    }

    private func timingRow(_ phase: (name: String, milliseconds: Double), maxMilliseconds: Double) -> some View {
        HStack(spacing: 8) {
            Text(phase.name)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .leading)
            Capsule()
                .fill(Color.accentColor.opacity(0.7))
                .frame(
                    width: max(2, CGFloat(phase.milliseconds / max(1, maxMilliseconds)) * 120),
                    height: 5
                )
            Text(HAREntry.milliseconds(phase.milliseconds))
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
    }

    private func headerList(_ headers: [HARHeader]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if headers.isEmpty {
                Text("None")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            ForEach(Array(headers.enumerated()), id: \.offset) { item in
                Text("\(item.element.name): \(item.element.value)")
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Hosts

    private func hostBreakdown(_ insights: HARInsights) -> some View {
        ToolkitCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ToolkitSectionLabel(text: "Top hosts")
                    Spacer()
                    Text("\(insights.hosts.count) hosts")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                ForEach(insights.hosts.prefix(8)) { host in
                    HStack(spacing: 10) {
                        Text(host.host)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                        Spacer()
                        Text("\(host.requests) req")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if host.failures > 0 {
                            Text("\(host.failures) failed")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        Text(HARTrafficAnalyzer.bytes(host.bytes))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 74, alignment: .trailing)
                        Text(HAREntry.milliseconds(host.averageMilliseconds))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func serverLine(_ server: String, connection: String?) -> String {
        guard let connection, !connection.isEmpty else { return "Server \(server)" }
        return "Server \(server) · \(connection)"
    }

    private func statusColor(_ entry: HAREntry) -> Color {
        if entry.response.status == 0 || entry.response.status >= 500 { return .red }
        if entry.response.status >= 400 { return .orange }
        if entry.isRedirect { return .secondary }
        return .green
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.title = "Open HAR archive"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "har") ?? .json,
            UTType(filenameExtension: "json") ?? .json,
        ]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.load(url)
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-HTTP-Report.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.markdownReport().write(to: url, atomically: true, encoding: .utf8)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LanFi-HTTP-Traffic.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    private func copyCurl(_ entry: HAREntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.curl(for: entry), forType: .string)
    }
}
