import AppKit
import SwiftUI

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

    private var selectedNetwork: KnownNetwork? {
        networks.first { $0.id == selectedSSID } ?? networks.first
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
        .sheet(item: $shareTarget) { network in
            KnownNetworkQRSheet(
                ssid: network.ssid,
                suggestedSecurity: security(for: network.ssid))
        }
    }

    private var header: some View {
        ToolkitHeaderBar {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(networks.count) saved networks")
                    .font(.callout.weight(.semibold))
                Text("Read-only: names come from System Settings. Passwords are never read.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } trailing: {
            AppButton("Reload", systemImage: "arrow.clockwise", isBusy: isLoading, isEnabled: !isLoading) {
                Task { await load() }
            }
        }
    }

    private var list: some View {
        List(selection: $selectedSSID) {
            ForEach(networks) { network in
                row(network)
                    .tag(network.id)
                    .contextMenu {
                        Button("Create QR Code…") { shareTarget = network }
                    }
            }
        }
        .listStyle(.inset)
    }

    private func row(_ network: KnownNetwork) -> some View {
        HStack(spacing: 8) {
            Image(systemName: matched(network.ssid) == nil ? "wifi.slash" : "wifi")
                .font(.system(size: 13))
                .foregroundColor(
                    matched(network.ssid) == nil ? .secondary : AppPalette.ok
                )
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(network.ssid)
                    .font(.callout)
                    .lineLimit(1)
                Text(
                    matched(network.ssid).map { "In range · \($0.bandLabel) ch \($0.channel)" }
                        ?? "Not in range"
                )
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var detail: some View {
        if let network = selectedNetwork {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detailHeader(network)
                    radioDetails(network)
                    qrCard(network)
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

    private func detailHeader(_ network: KnownNetwork) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.router")
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(network.ssid).font(.title2.bold()).textSelection(.enabled)
                Text("Saved in System Settings · names only")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ToolkitStatusPill(
                text: matched(network.ssid) == nil ? "Not in range" : "In range",
                tone: matched(network.ssid) == nil ? .neutral : .good)
        }
    }

    @ViewBuilder
    private func radioDetails(_ network: KnownNetwork) -> some View {
        if let match = matched(network.ssid) {
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

    private func qrCard(_ network: KnownNetwork) -> some View {
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
                    shareTarget = network
                }
            }
        }
    }

    private func matched(_ ssid: String) -> NetworkModel? {
        analyzer.networks
            .filter { $0.ssid == ssid }
            .max { $0.signal < $1.signal }
    }

    private func security(for ssid: String) -> WiFiQRPayload.Security {
        let value = matched(ssid)?.security.lowercased() ?? ""
        if value.contains("open") || value.contains("none") { return .open }
        if value.contains("wep") { return .wep }
        return .wpa
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
