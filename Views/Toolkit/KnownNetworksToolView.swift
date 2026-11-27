import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Read-only inventory of networks saved in System Settings. Selecting a row
/// opens everything LanFi can legitimately show: the saved name, whether it is
/// in range now, and the live radio details. Passwords are never read; the QR
/// sheet builds a guest code from a password the user types.
struct KnownNetworksToolView: View {
    @ObservedObject var analyzer: AnalyzerViewModel

    @State private var networks: [KnownNetwork] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSSID: String?
    @State private var shareTarget: KnownNetwork?
    @State private var filter: KnownNetworkFilter = .all
    @State private var sort: KnownNetworkSort = .name

    private var rows: [KnownNetworkRow] {
        KnownNetworksAnalysis.rows(saved: networks, visible: analyzer.networks)
    }

    private var visibleRows: [KnownNetworkRow] {
        KnownNetworksAnalysis.filtered(rows, filter: filter, sort: sort)
    }

    private var summary: KnownNetworksSummary {
        KnownNetworksAnalysis.summary(rows: rows, visible: analyzer.networks)
    }

    private var selectedRow: KnownNetworkRow? {
        visibleRows.first { $0.id == selectedSSID }
            ?? visibleRows.first
            ?? rows.first { $0.id == selectedSSID }
            ?? rows.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let errorMessage {
                ToolkitErrorBanner(message: errorMessage)
                    .appContentPadding()
                Spacer()
            } else if networks.isEmpty {
                ToolkitEmptyState(
                    icon: "wifi.router",
                    title: "No saved networks",
                    message:
                        "Join a network in System Settings and reload. LanFi lists saved names only and cannot show or export their passwords."
                )
                Spacer()
            } else {
                HSplitView {
                    list
                        .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await load() }
        .onAppear {
            if selectedSSID == nil { selectedSSID = networks.first?.id }
        }
        .onChange(of: filter) { _ in selectedSSID = visibleRows.first?.id }
        .onChange(of: sort) { _ in selectedSSID = visibleRows.first?.id }
        .sheet(item: $shareTarget) { network in
            KnownNetworkQRSheet(
                ssid: network.ssid,
                suggestedSecurity: security(for: network.ssid))
        }
    }

    private var header: some View {
        ToolkitHeaderBar {
            VStack(alignment: .leading, spacing: 2) {
                Text("Known networks")
                    .font(.headline)
                Text(summaryLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } trailing: {
            HStack(spacing: 8) {
                Picker("Filter", selection: $filter) {
                    ForEach(KnownNetworkFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Picker("Sort", selection: $sort) {
                    ForEach(KnownNetworkSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                AppButton("Export", systemImage: "square.and.arrow.up", tone: .secondary) {
                    export()
                }
                .disabled(visibleRows.isEmpty)
                AppButton("Reload", systemImage: "arrow.clockwise", isBusy: isLoading, isEnabled: !isLoading) {
                    Task { await load() }
                }
            }
        }
    }

    /// One plain caption instead of five figures squeezed into a fixed-height
    /// toolbar, where the block used to overflow its row and lose the top gap.
    private var summaryLine: String {
        var parts = [
            String(format: String(localized: "%lld saved"), summary.saved),
            String(format: String(localized: "%lld in range"), summary.inRange),
        ]
        if summary.insecure > 0 {
            parts.append(
                String(format: String(localized: "%lld weak security"), summary.insecure))
        }
        if summary.unsavedVisible > 0 {
            parts.append(
                String(format: String(localized: "%lld visible, not saved"), summary.unsavedVisible))
        }
        parts.append(String(localized: "Passwords are never read."))
        return parts.joined(separator: " · ")
    }

    private var list: some View {
        List(selection: $selectedSSID) {
            ForEach(visibleRows) { row in
                savedRow(row)
                    .tag(row.id)
                    .contextMenu {
                        Button("Create QR Code…") { shareTarget = KnownNetwork(ssid: row.ssid) }
                        Button("Copy SSID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.ssid, forType: .string)
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func savedRow(_ row: KnownNetworkRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.isInRange ? "wifi" : "wifi.slash")
                .font(.system(size: 13))
                .foregroundColor(row.isInRange ? AppPalette.ok : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.ssid)
                    .font(.callout)
                    .lineLimit(1)
                Text(
                    row.isInRange
                        ? "\(row.channelLabel) · \(row.bssidCount) BSSID\(row.bssidCount == 1 ? "" : "s")"
                        : "Not in range"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let signal = row.best?.signal {
                Text("\(signal)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(signal >= -67 ? AppPalette.ok : AppPalette.warning)
            }
            if row.security.isInsecure {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppPalette.warning)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        if let row = selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignToken.Spacing.medium) {
                    detailHeader(row)
                    securityCard(row)
                    radioDetails(row)
                    accessPointsCard(row)
                    unsavedCard
                    qrCard(row)
                }
                .appContentPadding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ToolkitEmptyState(
                icon: "wifi.router", title: "Select a network",
                message: "Pick a saved network to see its details.")
        }
    }

    private func detailHeader(_ row: KnownNetworkRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.router")
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.ssid).font(.title2.bold()).textSelection(.enabled)
                Text(
                    row.isInRange
                        ? "Saved in System Settings · \(row.bssidCount) BSSID\(row.bssidCount == 1 ? "" : "s") visible"
                        : "Saved in System Settings · not visible in the current scan"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer()
            ToolkitStatusPill(
                text: row.isInRange ? "In range" : "Not in range",
                tone: row.isInRange ? .good : .neutral)
        }
    }

    @ViewBuilder
    private func securityCard(_ row: KnownNetworkRow) -> some View {
        if row.isInRange, row.security.isInsecure {
            ToolkitCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundColor(AppPalette.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(row.ssid) uses a weak security mode")
                            .font(.callout.weight(.semibold))
                        Text(
                            row.security.isOpen
                                ? "The network is open; traffic is not encrypted over the air."
                                : row.security.isWEP
                                    ? "WEP is cryptographically broken."
                                    : "Legacy WPA should be replaced by WPA2/WPA3."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func radioDetails(_ row: KnownNetworkRow) -> some View {
        if let match = row.best {
            ToolkitCard {
                VStack(alignment: .leading, spacing: 10) {
                    ToolkitSectionLabel(text: "Live radio")
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading, spacing: 10
                    ) {
                        DetailRow(label: "Band", value: match.bandLabel)
                        DetailRow(label: "Channel", value: "\(match.channel)")
                        DetailRow(
                            label: "Width",
                            value: match.channelWidthLabel == "-"
                                ? "—" : "\(match.channelWidthLabel) MHz")
                        DetailRow(label: "Security", value: match.security)
                        DetailRow(
                            label: "BSSID",
                            value: match.bssid.isEmpty ? "—" : match.bssid)
                        DetailRow(label: "Signal", value: "\(match.signal) dBm")
                        DetailRow(
                            label: "Quality",
                            value: analyzer.metrics(for: match).map { "\($0.qualityScore)" } ?? "—")
                        DetailRow(label: "Generation", value: match.generationLabel)
                    }
                }
            }
        } else {
            ToolkitCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.slash").foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This network is not visible right now").font(.callout.weight(.semibold))
                        Text(
                            "System Settings still remembers it, but no beacon with this SSID is in the current scan. Move closer, enable the radio, or reload."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func accessPointsCard(_ row: KnownNetworkRow) -> some View {
        Group {
            if row.isInRange {
                ToolkitCard {
                    VStack(alignment: .leading, spacing: 8) {
                        ToolkitSectionLabel(text: "Access points")
                        ForEach(row.accessPoints.sorted { $0.signal > $1.signal }) { accessPoint in
                            HStack(spacing: 8) {
                                Text(accessPoint.bssid)
                                    .font(.caption2.monospaced())
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text("ch \(accessPoint.channel) · \(accessPoint.signal) dBm")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(accessPoint.security)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var unsavedCard: some View {
        let unsaved = KnownNetworksAnalysis.unsavedVisible(
            saved: networks, visible: analyzer.networks)
        if !unsaved.isEmpty {
            ToolkitCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ToolkitSectionLabel(text: "Visible, not saved")
                        Spacer()
                        Text("\(unsaved.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    ForEach(unsaved.prefix(6)) { network in
                        HStack(spacing: 8) {
                            Image(systemName: "wifi")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(network.ssid)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(network.bandLabel) ch \(network.channel) · \(network.signal) dBm")
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            if network.security.lowercased().contains("open") {
                                Text("Open")
                                    .font(.caption2)
                                    .foregroundColor(AppPalette.warning)
                            }
                        }
                    }
                    Text(
                        "These networks are in range but have no saved entry. Join them in System Settings if they belong to you."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private func qrCard(_ row: KnownNetworkRow) -> some View {
        ToolkitCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "qrcode")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Guest QR code").font(.callout.weight(.semibold))
                    Text(
                        "Create a QR code for guests. You type the password; LanFi does not read the saved one and never stores it."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                AppButton("Create QR…", systemImage: "qrcode", tone: .primary) {
                    shareTarget = KnownNetwork(ssid: row.ssid)
                }
            }
        }
    }

    private func security(for ssid: String) -> WiFiQRPayload.Security {
        let value = rows.first { $0.ssid == ssid }?.best?.security.lowercased() ?? ""
        if value.contains("open") || value.contains("none") { return .open }
        if value.contains("wep") { return .wep }
        return .wpa
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.nameFieldStringValue = "LanFi-known-networks.csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content: String
        if url.pathExtension.lowercased() == "json" {
            content = String(
                decoding: KnownNetworksAnalysis.json(rows: visibleRows), as: UTF8.self)
        } else {
            content = KnownNetworksAnalysis.csv(rows: visibleRows)
        }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let names = await Task.detached(priority: .userInitiated) {
            KnownNetworksService().preferredNetworks()
        }.value
        networks = names
        if selectedSSID == nil { selectedSSID = names.first?.id }
        if names.isEmpty {
            errorMessage =
                "macOS returned no saved networks. This can happen when Wi-Fi is off or System Settings has no preferred networks."
        }
        isLoading = false
    }
}

private struct KnownNetworkQRSheet: View {
    let ssid: String
    let suggestedSecurity: WiFiQRPayload.Security

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var security: WiFiQRPayload.Security = .wpa
    @State private var didCopy = false

    private var payload: String {
        WiFiQRPayload.string(ssid: ssid, password: password, security: security)
    }

    private var image: NSImage? {
        QRCode.image(for: payload, scale: 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Guest QR code").font(.title3.bold())
                Text("Scanning joins the network without typing the password.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    field("Network") {
                        Text(ssid)
                            .font(.callout)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    field("Security") {
                        Picker("Security", selection: $security) {
                            ForEach(WiFiQRPayload.Security.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                    field("Password") {
                        SecureField("Network password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 240)
                            .disabled(security == .open)
                    }
                    Text(
                        "The password is only used to build this code. LanFi does not store it and cannot read the saved password from System Settings."
                    )
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    AppButton(
                        didCopy ? "Copied" : "Copy payload",
                        isEnabled: security == .open || !password.isEmpty
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(payload, forType: .string)
                        didCopy = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    if let image {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: DesignToken.Radius.card))
                    } else {
                        Color.clear
                            .frame(width: 220, height: 220)
                            .appCardSurface()
                            .overlay(
                                Text("QR generation failed")
                                    .font(.caption)
                                    .foregroundColor(.secondary))
                    }
                    Text(payload)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(width: 220)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .appSheet(width: DesignToken.Layout.sheetWidth)
    }

    private func field<Content: View>(
        _ label: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            content()
        }
    }
}
